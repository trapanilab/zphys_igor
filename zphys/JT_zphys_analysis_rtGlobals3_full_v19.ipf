#pragma rtGlobals=3        // Full Igor Pro 9 cleanup version.
#include <Decimation>
#include <Waves Average>

// JT_zphys_analysis.ipf
//
// Analysis helpers for the Trapani Lab zPhys electrophysiology panel.
// Target environment: Igor Pro 9 on macOS.
//
// This module contains routines for:
//   - Baseline subtraction, sign flips, and time-zero scaling.
//   - Histograms and double-exponential fits of ISI waves.
//   - Concatenating, cropping, averaging, and decimating sweeps.
//   - Microphonic FFT/area analysis.
//   - Small utility routines used by graph and panel callbacks.
//
// Conservative cleanup notes:
//   - Existing public function names and control callbacks are preserved.
//   - Legacy/temporary helper routines are kept, but documented as such.
//   - Compile-risk fixes are marked inline with "cleanup:" comments.
//   - This file still assumes the globals created by JT_zphys_panel.ipf and
//     data loaded by JT_zphys_load.ipf.

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Ensure the global K0 parameter used by the held dblexp_XOffset fit exists
// before calling CurveFit with /H="1000". This avoids implicit-global failures
// when testing under stricter rtGlobals settings.
Function JT_SetDblExpYOffsetToZero()
	Variable /G K0 = 0
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Baseline Subtract a 2D wave via a linear fit to a drifting baseline
//fix this to have options!!!!

// Baseline-subtracts each column of a 2D wave with a linear fit, then displays
// the across-column average of the corrected sweeps.
Function Avg_2Dwave_BL(tempWaveName)
	String tempWaveName
	Wave /Z tWave = $tempWaveName
	If (!WaveExists(tWave))
		Abort "Avg_2Dwave_BL: input wave not found: "+tempWaveName
	Endif
	If (DimSize(tWave, 1) <= 0)
		Abort "Avg_2Dwave_BL expects a 2D wave."
	Endif

	Variable i
	Variable numRows = DimSize(tWave, 0)        // cleanup: original used undefined tempWave.
	Variable numCols = DimSize(tWave, 1)

	Duplicate /O tWave BaselineSubtracted
	Make /O /N=(numRows) tempCoefWave
	SetScale /P x, DimOffset(tWave, 0), DimDelta(tWave, 0), WaveUnits(tWave, 0), tempCoefWave

	For (i = 0; i < numCols; i += 1)
		CurveFit /Q/M=2/W=0 line, tWave[][i] /D
		Wave coef_Wave = W_coef
		tempCoefWave = coef_Wave[1]*x + coef_Wave[0]
		BaselineSubtracted[][i] = tWave[p][i] - tempCoefWave[p]
	Endfor

	// Average across columns after baseline subtraction.
	// cleanup v7: avoid MatrixOP expression syntax that Igor rejects under rtGlobals=3.
	Make /O /N=(numRows) AvgWave
	SetScale /P x, DimOffset(tWave, 0), DimDelta(tWave, 0), WaveUnits(tWave, 0), AvgWave
	AvgWave = 0
	For (i = 0; i < numCols; i += 1)
		AvgWave[p] += BaselineSubtracted[p][i]
	Endfor
	AvgWave /= numCols

	KillWaves /Z BaselineSubtracted, W_coef, W_sigma, fit_temp2D, tempCoefWave

	Display /W=(290,0,1290,400) /K=1 AvgWave
	ModifyGraph rgb=(0,0,0)
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Add a bunch of single 1D waves into one 2D wave
// Legacy hard-coded helper for packing a specific AJO040115 series into a 2D wave. Kept for reference.
Function tempAddWave(numCols)
	Variable numCols
	Variable i
	Wave tempWave = root:AJO040115:AJO040115_31:'AJO040115_1_31_1_1_Adc-1'
	Duplicate /O tempWave temp2D
	Wave temp2D
	Redimension /N=(-1,numCols) temp2D

	For (i=1;i<=numCols;i+=1)

		String tempW = "root:AJO040115:AJO040115_31:'AJO040115_1_31_"+num2str(i)+"_1_Adc-1'"
		Wave tW = $tempW
		temp2D[][i-1] = tW[p]

	Endfor
End


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Histogram: JT_Controls Panel

// Creates an ISI histogram from the main zPhys controls. If "Use concat.
// folder" is checked, the ISI wave is selected from root:A:Concat.
Function Hist1(ctrlName):ButtonControl

	String ctrlName
	String histwave
	String inputwave
	String ISIwave
	String valAsStr
	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder

	Variable binsize = 10
	Variable binnumber = 100
	Variable binstart = 0.000
	Variable pointnumber
	Variable pointstart = 1
	Variable checknum
	Variable i
	Variable ISI_avg

	String savedDataFolder = GetDataFolder(1)

	// Determine whether a concat-wave ISI will be analyzed.
	ControlInfo /W=zPhys_Settings check110
	checknum = V_Value

	If (checknum == 0)
		String ISIwaves = WaveList("*_ISI", ";", "")
		ISIwave = StringFromList(0, ISIwaves)
		Wave /Z wavecheck1 = $ISIwave
		If (WaveExists(wavecheck1))
			Prompt inputwave, "Input Wave", popup WaveList("*_ISI", ";", "")
		Else
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
		Endif
	Elseif (checknum == 1)
		SetDataFolder root:A:Concat:
		String concatISIwaves = WaveList("*_ISI", ";", "")
		String concatISIwave = StringFromList(0, concatISIwaves)
		Wave /Z wavecheck2 = $concatISIwave
		If (WaveExists(wavecheck2))
			Prompt inputwave, "Input Wave", popup WaveList("*_ISI", ";", "")
		Else
			SetDataFolder savedDataFolder
			Abort "No ISI waves were found in root:A:Concat."
		Endif
	Endif

	DoPrompt "Select ISI wave", inputwave
	If (V_flag != 0)
		SetDataFolder savedDataFolder
		Return 0
	Endif

	Wave /Z w = $inputwave
	If (!WaveExists(w))
		SetDataFolder savedDataFolder
		Abort "Selected ISI wave was not found: "+inputwave
	Endif

	pointnumber = numpnts(w)
	If (pointnumber <= 0)
		SetDataFolder savedDataFolder
		Abort "Selected ISI wave has no points."
	Endif

	// Calculate average ISI in milliseconds.
	For (i = 0; i < pointnumber; i += 1)
		ISI_avg += w[i]
	Endfor
	ISI_avg = (ISI_avg / pointnumber) * 1000
	sprintf valAsStr, "%.3g", ISI_avg
	ISI_avg = str2num(valAsStr)

	Prompt binsize, "Bin width (milliseconds):"
	Prompt binnumber, "Number of bins:"
	Prompt binstart, "Start bin at:"
	Prompt pointnumber, "Number of points to bin:"
	Prompt pointstart, "Start binning at point #:"
	DoPrompt "Create Histogram", binsize, binnumber, binstart, pointnumber, pointstart

	If (V_flag == 0)
		If (binsize <= 0 || binnumber <= 0 || pointnumber <= 0)
			SetDataFolder savedDataFolder
			Abort "Histogram settings must be greater than zero."
		Endif

		histwave = inputwave + "_H"
		Make /O /N=(binnumber) $histwave
		Wave newhistwave = $histwave

		binsize = binsize / 1000 // convert ms to seconds
		Histogram /R=[pointstart,pointnumber]/B={binstart,binsize,binnumber} /C $inputwave, $histwave

		ControlInfo /W=zPhys_Settings check100
		checknum = V_Value
		If (checknum < 1)
			Display /N=hist_graph /W=(1000,600,1600,900) /K=1 $histwave
			ModifyGraph mode=5, rgb=(32768,32770,65535), hbFill=2, useBarStrokeRGB=1
			ModifyGraph offset($NameOfWave(newhistwave))={-deltaX(newhistwave),0}

			Variable yMax = WaveMax(newhistwave)
			FindValue /V=(yMax) newhistwave
			yMax = pnt2X(newhistwave, V_value)
			Cursor A $histwave yMax
			Cursor /P B $histwave (binnumber - 1)
			ShowInfo
			SetAxis /A/N=0/E=1 bottom
			Label left "Number of Events"
			Label bottom "Time (s)"
			TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg ISI = "+num2str(ISI_avg)+" ms"
		Else
			AppendToGraph /C=(0,50000,2500) $histwave
		Endif

		JT_SetDblExpYOffsetToZero()
		CurveFit/NTHR=0/TBOX=768 /H="1000" dblexp_XOffset $histwave [pcsr(A),pcsr(B)] /D
	Endif
	SetDataFolder savedDataFolder
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Histogram for Graph Control Panel
// Prompts for histogram settings, then delegates to Hist3.
Function Hist2(ctrlName):ButtonControl
	string ctrlName
	variable binsize = 10
	variable binnumber = 100
	variable binstart = 0.000
	variable pointnumber
	variable pointstart = 1

	//Prompt for Histogram values
	Prompt binsize, "Bin width (milliseconds):"
	Prompt binnumber, "Number of bins:"
	Prompt binstart, "Start bin at:"
	Prompt pointnumber, "Number of points to bin:"
	Prompt pointstart, "Start binning at point #:"
	DoPrompt "Create Histogram", binsize, binnumber, binstart, pointnumber, pointstart

	If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
		Abort "Cancel clicked!"
	ElseIf (binsize==0||binnumber==0)
		Abort "Wrong bin attributes!"
	Endif

	Hist3(ctrlName,binsize,binnumber,binstart,pointnumber,pointstart)
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Histogram for Graph Control Panel

// Programmatic histogram helper used by graph-control callbacks.
Function Hist3(ctrlName,binsize,binnumber,binstart,pointnumber,pointstart):ButtonControl
	String ctrlName
	Variable binsize
	Variable binnumber
	Variable binstart
	Variable pointnumber
	Variable pointstart

	String dfinputname = ""
	String inputwave
	String inputname
	String histname
	String histwave
	String valAsStr
	Variable ISI_avg

	If (cmpstr(ctrlName, "phistogram") == 0)
		Wave /Z wave1 = WaveRefIndexed("", 0, 3)
		If (!WaveExists(wave1))
			Abort "No trace was found in the top graph for histogram analysis."
		Endif
		inputname = PossiblyQuoteName(NameOfWave(wave1) + "_ISI")
		dfinputname = GetWavesDataFolder(wave1, 1)
		inputwave = dfinputname + inputname
		Wave /Z inputISI = $inputwave
		If (!WaveExists(inputISI))
			Abort "Could not find ISI wave: "+inputwave
		Endif
		pointnumber = numpnts(inputISI)
		ISI_avg = 1000 * mean(inputISI)
		sprintf valAsStr, "%.3g", ISI_avg
		ISI_avg = str2num(valAsStr)
		histname = PossiblyQuoteName(NameOfWave(wave1) + "_H" + num2str(binnumber))
		histwave = dfinputname + histname
	Else
		inputname = PossiblyQuoteName(ctrlName)
		inputwave = inputname
		Wave /Z inputW = $inputwave
		If (!WaveExists(inputW))
			Abort "Histogram input wave was not found: "+ctrlName
		Endif
		histname = PossiblyQuoteName(ctrlName + "_H" + num2str(binnumber))
		histwave = histname
	Endif

	If (binsize <= 0 || binnumber <= 0 || pointnumber <= 0)
		Abort "Histogram settings must be greater than zero."
	Endif

	binsize = binsize / 1000 // convert ms to seconds
	Histogram /R=[pointstart,pointnumber]/B={binstart,binsize,binnumber} /C /DEST=$(histwave) $(inputwave)
	Wave newhistwave = $histwave

	If (cmpstr(ctrlName, "phistogram") == 0)
		Display /N=hist_graph /W=(1000,600,1600,900) /K=1 $histwave
		ModifyGraph mode=5, rgb=(32768,32770,65535), hbFill=2, useBarStrokeRGB=1
		ModifyGraph offset($NameOfWave(newhistwave))={-deltaX(newhistwave),0}

		Variable yMax = WaveMax(newhistwave)
		Variable yMin = WaveMin(newhistwave)
		FindValue /V=(yMax) newhistwave
		yMax = pnt2X(newhistwave, V_value)
		FindValue /V=(yMin) newhistwave
		yMin = pnt2X(newhistwave, V_value)
		If (yMin < yMax)
			yMin = pnt2X(newhistwave, DimSize(newhistwave, 0) - 1)
		Endif
		Cursor A $histwave yMax
		Cursor B $histwave yMin
		ShowInfo
		SetAxis /A/N=0/E=1 bottom
		Label left "Number of Events"
		Label bottom "Time (s)"
		TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg ISI = "+num2str(ISI_avg)+" ms"

		JT_SetDblExpYOffsetToZero()
		CurveFit/NTHR=0/TBOX=768 /H="1000" dblexp_XOffset $histwave [pcsr(A),pcsr(B)] /D
	Else
		Return 1
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Concatenate Waves


// Concatenates selected columns from the current 2D sweep wave into root:A:Concat.
Function concat1(ctrlName): ButtonControl
	String ctrlName
	String concatwavepath
	String concatname
	String topGraph
	Variable tempwavenum1
	Variable tempwavenum2
	Variable checknum
	Variable i

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type

	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent
	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR /Z sweepTime

	String savedDataFolder = GetDataFolder(1)

	tempwavenum1 = sweepStartnum
	tempwavenum2 = sweepEndnum
	Prompt tempwavenum1, "First wave:"
	Prompt tempwavenum2, "Last wave:"
	DoPrompt "Concatenate Waves", tempwavenum1, tempwavenum2

	If (V_flag == 0)
		ControlInfo /W=zPhys_Settings check107
		Variable checknum107 = V_Value
		If (checknum107 == 1)
			Plot_Waves(tempwave, tempwavenum1, tempwavenum2)
			topGraph = WinName(0, 1)
			cropWaves(topGraph, tempwavenum1, tempwavenum2)
			DoWindow /K $topGraph
		Endif

		Wave /Z temp2DWave = $(tempwave)
		If (!WaveExists(temp2DWave))
			SetDataFolder savedDataFolder
			Abort "Current 2D wave was not found: "+tempwave
		Endif
		If (tempwavenum1 < 1 || tempwavenum2 < tempwavenum1 || tempwavenum2 > DimSize(temp2DWave, 1))
			SetDataFolder savedDataFolder
			Abort "Requested sweep range is outside the current 2D wave."
		Endif

		concatname = tempwave + "_C" + num2str(tempwavenum1) + "to" + num2str(tempwavenum2)
		concatwavepath = "root:A:Concat:"
		String concatFullPath = concatwavepath + PossiblyQuoteName(concatname)
		Variable waveDelta = DimDelta(temp2DWave, 0)

		MatrixOP /O $(concatFullPath) = col(temp2DWave, tempwavenum1 - 1)
		SetScale /P x 0, waveDelta, "s", $(concatFullPath)

		For (i = tempwavenum1; i < tempwavenum2; i += 1)
			MatrixOP/FREE tempcol = col(temp2DWave, i)
			Concatenate /NP {tempcol}, $(concatFullPath)
		Endfor

		ControlInfo /W=zPhys_Settings check102
		checknum = V_Value
		If (checknum == 0)
			Plot_Waves(concatFullPath, 1, 1)
		Else
			SetDataFolder root:A:Concat:
			String source
			Prompt source, "Source Wave", popup WaveList("!*D*", ";", "")
			Variable factor = 10
			Prompt factor, "Decimation factor"
			DoPrompt "Decimate Concat Wave", source, factor
			If (V_flag != 0)
				SetDataFolder savedDataFolder
				Return 0
			Endif
			String destName = source + "dec"
			Variable XPos = 2
			Variable StdevOpts = 1
			PauseUpdate; Silent 1
			FDecimateXPosStd($source, destName, factor, XPos, StdevOpts)
			PauseUpdate; Silent 1

			KillWaves /Z $source

			Display /W=(290,0,1290,400) /K=1 $destName
			ModifyGraph rgb=(0,0,0)
			SetAxis/A/N=0/E=1 bottom
			SetAxis/A/N=2/E=0 left
			Label left "Current"
			Label bottom "Time"
			Cursor A, $destName, leftx($destName)
			Cursor B, $destName, numpnts($destName)-1
			ShowInfo
			SetDrawLayer UserFront
			SetDrawEnv xcoord=rel, ycoord=left, linefgc=(65535,0,0), dash=1
			DrawLine 0,eventAmp,1,eventAmp
		Endif

		topGraph = WinName(0, 1)
		Graph_Panel(topGraph)
		Button pfindpeaks, disable=0
		Checkbox checkH3, disable=0
		Slider slider1, disable=0, limits={spikeamp,0,0}
	Endif
	SetDataFolder savedDataFolder
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Analyze microphonics with FFT or Area under curve


// Analyzes microphonics in one or more graphs using area-under-curve or FFT.
Function fft_wave1(ctrlName):ButtonControl
	String ctrlName
	String FFTwave
	String cursorNames = "AB"

	Variable tempvar0, tempvar1
	Variable offset
	Variable j, n
	Variable temp, temp1
	Variable leftval, rightval
	Variable startXval = 0.05
	Variable deltaXval = 0.25
	Variable baselineVal = 0.05

	String graphs = WinList("*", ";", "WIN:1")
	String topGraph = WinName(0, 1)

	Prompt tempvar0, "Which microphonic analysis", popup "Area under curve;FFT"
	If (ItemsInList(graphs) == 0)
		Abort "No graphs to analyze!"
	Elseif (cmpstr(ctrlName, "pFFT") == 0)
		Prompt tempvar1, "Current graph:", popup topGraph
	Elseif (ItemsInList(graphs) > 1)
		Prompt tempvar1, "Select graph(s):", popup "Top graph;All graphs"
	Else
		Prompt tempvar1, "Top graph:", popup topGraph
	Endif
	Prompt baselineVal, "Set baseline duration for zeroing:"
	Prompt startXval, "Set left cursor:"
	Prompt deltaXval, "Set cursor spacing:"
	DoPrompt "Analyze microphonics:", baselineVal, tempvar0, tempvar1, startXval, deltaXval

	If (V_flag == 0)
		If (tempvar1 == 1)
			graphs = topGraph + ";"
		Endif

		For (j = 0; j < ItemsInList(graphs); j += 1)
			String graph = StringFromList(j, graphs)
			If (cmpstr(graph[0,2], "FFT") == 0)
				Continue
			Endif
			String graphtraces = TraceNameList(graph, ";", 1)
			If (ItemsInList(graphtraces) == 0)
				Continue
			Endif
			String temptrace = StringFromList(0, graphtraces)
			Wave /Z tempWave = WaveRefIndexed(graph, 0, 1)
			If (!WaveExists(tempWave))
				Continue
			Endif
			String tempWaveName = GetWavesDataFolder(tempWave, 2)

			For (n = 0; n < 2; n += 1)
				Cursor /H=2 /S=1 /C=(65535,0,0) /W=$graph $(cursorNames[n]), $(temptrace), startXval + n*deltaXval
			Endfor

			If (tempvar0 == 2)
				leftval = pcsr(A, graph)
				rightval = pcsr(B, graph)
				temp = (rightval - leftval) / 2
				temp1 = temp - floor(temp)
				If (temp1 == 0)
					rightval = rightval - 1
				Endif

				FFTwave = "root:A:FFT1:" + temptrace + "_FFT"
				Make /O /N=(rightval-leftval) $FFTwave
				FFT /RP=[leftval,rightval] /OUT=4 /DEST=$FFTwave $tempWaveName
				Display /N=FFT_graph /W=(900,500,1400,700) /K=1 $FFTwave
				ModifyGraph grid=1, log(bottom)=1, log(left)=1, rgb=(0,0,0)
				SetAxis /A=2 /N=2 bottom
				SetAxis /A=2 /N=2 left
				Label left "Power (V\\S2\\M/ Hz)"
				AppendToTable /W=FFT_table $FFTwave.id
				DoWindow /F FFT_table
			Elseif (tempvar0 == 1)
				leftval = xcsr(A, graph)
				rightval = xcsr(B, graph)
				offset = mean(tempWave, 0, baselineVal)
				tempWave = tempWave - offset
				Print "Area = "+num2str(area($tempWaveName, leftval, rightval)) + " volt-sec"
				Print "Average potential = "+num2str((area($tempWaveName, leftval, rightval))/(rightval-leftval))+" volts"
			Endif
		Endfor
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Average Waves: For JT_Controls panel


// Averages all columns in the current 2D sweep wave into root:A:Avg.
Function average1(ctrlName): ButtonControl
	String ctrlName
	String avgwavename
	String avgwave

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type
	SVAR /Z FileNameTruncated

	If (SVAR_Exists(FileNameTruncated))
		avgwavename = FileNameTruncated + "_Avg"
	Else
		avgwavename = tempwave + "_Avg"
	Endif
	avgwave = "root:A:Avg:" + PossiblyQuoteName(avgwavename)

	Wave /Z temp2DWave = $(tempwave)
	If (!WaveExists(temp2DWave))
		Abort "Current 2D wave was not found: "+tempwave
	Endif
	If (DimSize(temp2DWave, 1) <= 0)
		Abort "average1 expects a 2D wave."
	Endif

	MatrixOP /O nanDelWave = replaceNaNs(temp2DWave, 0)
	MatrixOP /O $(avgwave) = sumRows(nanDelWave) / numcols(nanDelWave)
	SetScale /P x, DimOffset(temp2DWave, 0), DimDelta(temp2DWave, 0), "s", $(avgwave)
	KillWaves /Z nanDelWave

	Wave avgWaveRef = $avgwave
	Display /W=(290,0,1290,400) /K=1 avgWaveRef
	ModifyGraph rgb=(0,0,0)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=2/E=2 left
	Label bottom "Time"
	Cursor /P A, avgWaveRef, (0.15 / DimDelta(avgWaveRef, 0))
	ShowInfo

	String topGraph = WinName(0, 1)
	Graph_Panel(topGraph)
	Button pfft, pos={200,5}, disable=0
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Baseline Waves

// Baseline-subtracts the current wave or selected columns of the current 2D wave in place.
Function base1(ctrlName): ButtonControl
	string ctrlName
	string tempstring1
	string tempfolder1
	string cursors
	string cmd

	variable checknum
	variable tempwavenum1
	variable tempwavenum2
	variable baseval
	variable i
	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	//Baseline waves = THIS WILL OVERWRITE THE ORIGINAL WAVES (may change in future...)

	tempfolder1 = GetDataFolder(0)

	If (cmpstr (tempfolder1,"root")==0)
		Wave temp1 = $tempwave
		baseval = mean (temp1)
		temp1 = temp1-baseval

		//If Sign checkbox is checked, flip sign of wave
		controlInfo /W=zPhys_Settings check101
		checknum = V_Value
		If (checknum==1)
			temp1 = -1*temp1
		Endif

	Else

		//These globals are within the current data folder:
		SVAR /Z FileNameTruncated

		//Determine if  "Multiple" is checked
		controlInfo /W=JT_Controls check201
		variable checknum201 = V_Value
		If(checknum201==1)
			tempwavenum1 = sweepStartnum
			tempwavenum2 = sweepEndnum
		Else
			tempwavenum1 = sweepCurrent
			tempwavenum2 = sweepCurrent
		Endif

		Prompt tempwavenum1, "First wave:"
		Prompt tempwavenum2, "Last wave:"
		Prompt cursors, "Use mean between cursors?", popup "no;yes"
		DoPrompt "Baseline Waves (Overwrite)", tempwavenum1, tempwavenum2, cursors

		If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

			WAVE /Z temp2DWave = $(tempwave)

			Variable A_val = 0 //= xcsr(A)
			Variable B_val = 0.15 //= xcsr(B)

			For	(i=tempwavenum1-1; i<tempwavenum2; i+=1)

				//parse out one wave at a time from the 2D wave in order to use FindLevels
				MatrixOP/FREE temp1 = col(temp2DWave, i)

				If (cmpstr(cursors,"yes")==0)
					baseval = mean (temp1,(A_val),(B_val))
				Else
					baseval = (mean (temp1))
				Endif

				temp2DWave[0, numpnts(temp1)-1][i]=temp1[p]-baseval
			Endfor

		Endif
	Endif
End

/////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
//concat function by Adam Light @ WaveMetrics 04/24/10

// Stitches a semicolon-separated list of 1D sweeps into an existing destination wave.
// Original implementation by Adam Light, WaveMetrics, 2010; kept for legacy paths.
Function StitchSweeps(waveListToStitch, destWave)
	String waveListToStitch
	Wave destWave

	Variable numWaves = ItemsInList(waveListToStitch, ";")
	If (numWaves <= 0)
		Print "No waves were supplied for stitching."
		Return -1
	Endif

	Wave /Z firstWave = $(StringFromList(0, waveListToStitch, ";"))
	If (!WaveExists(firstWave))
		Print "Could not create a wave reference for the first wave in the list."
		Return -1
	Endif
	Variable startTimer = DimOffset(firstWave, 0)

	Wave /Z lastWave = $(StringFromList(numWaves - 1, waveListToStitch, ";"))
	If (!WaveExists(lastWave))
		Print "Could not create a wave reference for the last wave in the list."
		Return -1
	Endif

	Variable stopTimer = DimOffset(lastWave, 0) + (2 * (DimSize(lastWave, 0) * DimDelta(lastWave, 0)))
	Variable totalDurationTimer = stopTimer - startTimer
	Variable newWaveNumPoints = totalDurationTimer / DimDelta(lastWave, 0)
	Redimension /N=(newWaveNumPoints) destWave
	destWave = NaN
	SetScale /P x, 0, DimDelta(firstWave, 0), WaveUnits(firstWave, 0), destWave

	Variable n
	Variable realPointCounter = 0
	Variable startIndex, endIndex
	Variable firstTimestamp = DimOffset(firstWave, 0)
	Variable startingTimestamp
	For (n = 0; n < numWaves; n += 1)
		Wave /Z thisWave = $(StringFromList(n, waveListToStitch, ";"))
		If (WaveExists(thisWave))
			startingTimestamp = DimOffset(thisWave, 0) - firstTimestamp
			If (numtype(startingTimestamp) == 0)
				startIndex = x2pnt(destWave, startingTimestamp)
				endIndex = startIndex + DimSize(thisWave, 0) - 1
				destWave[startIndex, endIndex] = thisWave[p - startIndex]
				realPointCounter = max(realPointCounter, startIndex + DimSize(thisWave, 0))
			Else
				Printf "Could not determine the beginning timer value of wave %s, so it was skipped.\r", StringFromList(n, waveListToStitch, ";")
				Return -1
			Endif
		Else
			Printf "Wave %s was not found, so it has not been incorporated into destWave.\r", StringFromList(n, waveListToStitch, ";")
		Endif
	Endfor

	If (realPointCounter > 0)
		Redimension /N=(realPointCounter) destWave
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////////
//Set each wave to time = 0; JT
// adapted from concat function by Adam Light @ WaveMetrics 04/24/10


// Checkbox callback to zero x scaling and/or flip sign of the current input/stim waves.
Function ZeroSweeps(ctrlName,checked) : CheckBoxControl
	String ctrlName
	Variable checked
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR tempwave = root:A:tempwave
	SVAR data_type = root:A:data_type
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent
	NVAR /Z sweepTime
	SVAR /Z FileNameTruncated
	String waveListToZero = ""
	String candidate
	Variable i, n, j
	DFREF savedDF = GetDataFolderDFR()

	If (cmpstr(ctrlName, "coumns") == 0 || cmpstr(ctrlName, "columns") == 0)
		SetDataFolder root:A:Avg
		String listofWaves = WaveList("*", ";", "")
		If (cmpstr(listofWaves, "") == 0)
			SetDataFolder savedDF
			Abort "No waves found in root:A:Avg."
		Endif
		For (j = 0; j < ItemsInList(listofWaves); j += 1)
			String tempcolumnwave = StringFromList(j, listofWaves)
			Wave columnWave = $tempcolumnwave
			SetScale /P x, 0, DimDelta(columnWave, 0), WaveUnits(columnWave, 0), columnWave
		Endfor
	Else
		// Prefer the actual wave currently selected by the panel.
		// Some workflows load a full wave name into root:A:tempwave without also
		// filling root:A:input_type/stim_type, so relying only on FileNameTruncated+input_type
		// can make Find_Peaks abort before it ever analyzes the trace.
		If (strlen(tempwave) > 0)
			Wave /Z panelWave = $tempwave
			If (WaveExists(panelWave))
				waveListToZero += tempwave + ";"
			Endif
		Endif

		If (SVAR_Exists(FileNameTruncated))
			// Always test FileNameTruncated+input_type, even when input_type is empty.
			// SutterPatch loads can intentionally use an empty input_type, making the
			// input wave name simply FileNameTruncated.
			candidate = FileNameTruncated + input_type
			Wave /Z inputWave2D = $candidate
			If (WaveExists(inputWave2D) && WhichListItem(candidate, waveListToZero) < 0)
				waveListToZero += candidate + ";"
			Endif

			// Legacy 1D-per-sweep naming, e.g. FileNameTruncated+"_"+sweep+input_type.
			// Only search this form when input_type is non-empty; otherwise this would
			// create broad names such as FileNameTruncated+"_1" that are not used by
			// the current 2D Sutter/HEKA/ABF loaders.
			If (strlen(input_type) > 0)
				For (i = sweepStartnum; i <= sweepEndnum; i += 1)
					candidate = FileNameTruncated + "_" + num2str(i) + input_type
					Wave /Z inputWave1D = $candidate
					If (WaveExists(inputWave1D) && WhichListItem(candidate, waveListToZero) < 0)
						waveListToZero += candidate + ";"
					Endif
				Endfor
			Endif

			If (strlen(stim_type) > 0 && cmpstr(stim_type, "_") != 0)
				candidate = FileNameTruncated + stim_type
				Wave /Z stimWave2D = $candidate
				If (WaveExists(stimWave2D) && WhichListItem(candidate, waveListToZero) < 0)
					waveListToZero += candidate + ";"
				Endif

				For (i = sweepStartnum; i <= sweepEndnum; i += 1)
					candidate = FileNameTruncated + "_" + num2str(i) + stim_type
					Wave /Z stimWave1D = $candidate
					If (WaveExists(stimWave1D) && WhichListItem(candidate, waveListToZero) < 0)
						waveListToZero += candidate + ";"
					Endif
				Endfor
			Endif
		Endif

		If (ItemsInList(waveListToZero) <= 0)
			SetDataFolder savedDF
			Abort "Could not find the selected wave to zero/flip. Check root:A:tempwave, root:A:input_type, and the current data folder."
		Endif

		Wave /Z firstWave = $(StringFromList(0, waveListToZero, ";"))
		If (!WaveExists(firstWave))
			SetDataFolder savedDF
			Abort "First wave for zeroing was not found: " + StringFromList(0, waveListToZero, ";")
		Endif

		For (n = 0; n < ItemsInList(waveListToZero); n += 1)
			Wave /Z thisWave = $(StringFromList(n, waveListToZero, ";"))
			If (WaveExists(thisWave))
				If ((cmpstr(ctrlName, "check106") == 0 && checked == 1) || (cmpstr(ctrlName, "ctrlName") == 0 && checked == 2))
					SetScale /P x, 0, DimDelta(firstWave, 0), WaveUnits(firstWave, 0), thisWave
					If (NVAR_Exists(sweepTime))
						sweepTime = 1
						Checkbox check106 value=sweepTime, disable=2*sweepTime, win=zPhys_Settings
					Endif
				Endif
				If (cmpstr(ctrlName, "check101") == 0 && checked < 2)
					thisWave = -1 * thisWave
				Endif
			Else
				Printf "Wave %s was not found, so it was skipped.\r", StringFromList(n, waveListToZero, ";")
			Endif
		Endfor
	Endif
	SetDataFolder savedDF
End
////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Legacy manual concatenation utility for numbered 1D waves.
Function concatenateTEMP()

	variable tempwavenum1 = 1888
	variable tempwavenum2 = 1942
	variable i, baseval
	string tempwave
	string concatwave
	string /G concatstring = ""
	string FileNameTruncated = "IN_Vclamp-"

	Prompt tempwavenum1, "First wave:"
	Prompt tempwavenum2, "Last wave:"
	Prompt FileNameTruncated, "Starting string"
	DoPrompt "Concatenate Waves", tempwavenum1, tempwavenum2, FileNameTruncated
	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		concatwave = FileNameTruncated+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_concat"
		Make /O $concatwave

		//Baseline

		For	(i=tempwavenum1; i<=tempwavenum2; i+=1)

			tempwave = FileNameTruncated+num2str(i)+" (A)"
			Wave temp1 = $tempwave
			baseval = mean (temp1)
			temp1 = temp1-baseval
		Endfor

		//Concatenate
		For (i=tempwavenum1; i<= tempwavenum2; i+=1)
			concatstring += FileNameTruncated+num2str(i)+" (A)"+";"
		Endfor
		//Concatenate the waves and send to the output concat wave
		Concatenate /NP /O concatstring, $concatwave

		//Graph
		Display /W=(200,0,1000,600) /K=1 $concatwave
		ModifyGraph rgb=(0,0,0)
		ModifyGraph tick=3,noLabel=2,axThick=0;DelayUpdate
		ModifyGraph margin=-1
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


// Legacy one-dimensional averaging helper. Kept as a manual utility.
Function averageTEMP(ctrlName)
	String ctrlName

	String FileNameTruncated = ctrlName
	Variable tempwavenum1 = 1
	Variable tempwavenum2 = 100
	Variable waveCount
	Variable i, n

	Prompt FileNameTruncated, "Wavename:"
	Prompt tempwavenum1, "Start wave:"
	Prompt tempwavenum2, "End wave:"
	DoPrompt "Average Waves", FileNameTruncated, tempwavenum1, tempwavenum2

	If (V_flag == 0)
		String avgwavename = FileNameTruncated + "_Avg"
		Wave /Z thePointWave = $(FileNameTruncated + num2str(tempwavenum1))
		If (!WaveExists(thePointWave))
			Abort "First wave was not found: "+FileNameTruncated+num2str(tempwavenum1)
		Endif

		Make /O /N=(numpnts(thePointWave)) $avgwavename = 0
		SetScale /P x, DimOffset(thePointWave, 0), DimDelta(thePointWave, 0), WaveUnits(thePointWave, 0), $avgwavename
		Wave avgwave = $avgwavename
		waveCount = 0

		For (i = tempwavenum1; i <= tempwavenum2; i += 1)
			Wave /Z tempwave = $(FileNameTruncated + num2str(i))
			If (WaveExists(tempwave) && WaveType(tempwave) != 0)
				For (n = 0; n < numpnts(tempwave); n += 1)
					If (NumType(tempwave[n]) != 2)
						avgwave[n] += tempwave[n]
					Endif
				Endfor
				waveCount += 1
			Else
				Print FileNameTruncated+num2str(i)+" was skipped because it is not a numeric wave."
			Endif
		Endfor

		If (waveCount <= 0)
			Abort "No numeric waves were available to average."
		Endif
		avgwave = avgwave / waveCount

		Display /W=(200,0,1000,600) /K=1 avgwave
		ModifyGraph rgb=(0,0,0)
		SetAxis/A/N=0/E=0 bottom
		SetAxis/A/N=2/E=2 left
		Label bottom "Time"
		ShowInfo
	Endif
End
//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
//From RGerkin : http://www.igorexchange.com/node/1466
// Removes a wave from open graphs before killing it. Source noted in original comments.
function ReallyKillWaves(w)
	wave w
	variable i,j

	string name=nameofwave(w)

	string graphs=WinList("*",";","WIN:1") // A list of all graphs
	for(i=0;i<itemsinlist(graphs);i+=1)
		string graph=stringfromlist(i,graphs)
		string traces=TraceNameList(graph,";",0)
		string tracematch = listmatch(traces,name)
		if(cmpstr(tracematch,name)==0) // Assumes that each wave is plotted at most once on a graph.
			RemoveFromGraph /W=$graph $name
		endif
	endfor

	//  string tables=WinList("*",";","WIN:2") // A list of all tables
	//  for(i=0;i<itemsinlist(tables);i+=1)
	//    string table=stringfromlist(i,tables)
	//    j=0
	//    do
	//      string column=StringByKey(table,j)
	//      if(strlen(column))
	//        RemoveFromTable /Z/W=$table $column
	//        j+=1
	//      else
	//        break
	//      endif
	//    while(1)
	//  endfor

	killwaves /z w
end


//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
// GraphWaveList(graphNameStr, matchStr, xOnly, yOnly, separatorStr)
//	Returns a string containing a list of waves in the specified graph which fit
//	certain criteria. Use this when you want only x waves or only y waves.
//	If you want all waves, you can use the built-in WaveList function instead.
//		graphNameStr can be the name of a graph or "" for the top graph
//		matchStr is "*" to match any wave or some pattern to match only selected waves
//		pass 1 for xOnly if you want only waves furnishing the x part of an XY pair
//		pass 1 for yOnly if you want only waves furnishing the y part of an XY pair
//		separatorStr is normally ";" or ","
// Returns waves in a graph matching optional x/y-wave criteria.
Function/S GraphWavesList(graphNameStr, matchStr, xOnly, yOnly, separatorStr)
	String graphNameStr
	String matchStr
	Variable xOnly, yOnly
	String separatorStr

	String list1, list2, w
	Variable i
	Variable waveTypeCode

	if (strlen(graphNameStr) == 0)
		graphNameStr = WinName(0, 1)
	endif
	if (WinType(graphNameStr) != 1)
		return ""				// bad graph name
	endif

	// Apply matchStr and graphNameStr criteria
	list1 = WaveList(matchStr, separatorStr, "WIN:" + graphNameStr)

	// Figure out which type of waves we want
	waveTypeCode = 0
	if (yOnly)
		waveTypeCode = 1
	endif
	if (xOnly)
		waveTypeCode = 2
	endif
	if (waveTypeCode == 0)
		list2 = list1
	else
		// Now apply the xOnly or yOnly criterion
		list2 = ""
		i = 0
		do
			w = WaveName(graphNameStr, i , waveTypeCode)
			if (strlen(w) == 0)
				break							// no more waves
			endif
			if (strsearch(list1, w, 0) >= 0)
				list2 += w + separatorStr
			endif
			i += 1
		while (1)
	endif

	return list2
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Crop waves
// Crops selected sweeps after user-adjusted cursors. Legacy 1D-sweep path; test before relying on 2D data.
Function cropWaves(ctrlName,tempwavenum1,tempwavenum2)
	String ctrlName
	variable tempwavenum1
	variable tempwavenum2

	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type

	string tempstring1
	string cropstring
	string cmd

	variable i,tempnum1

	String currentDF = GetDataFolder(1)	// Save

	//Create truncated name from tempwave
	//Get wave from wave in graph
	Wave /Z wave1 = WaveRefIndexed(ctrlName,0,3)
	If (!WaveExists(wave1))
		SetDataFolder currentDF
		Abort "cropWaves: no wave was found in the selected graph."
	Endif
	string inputname= NameofWave(wave1)
	string dfinputname = GetWavesDataFolder(wave1,1)

	SetDataFolder dfinputname
	//These globals are within the current data folder:

	NVAR /Z sweepStartnum
	NVAR /Z sweepEndnum
	NVAR /Z d
	NVAR /Z f
	NVAR /Z sweepTime

	SVAR /Z FileNameTruncated
	If (!SVAR_Exists(FileNameTruncated))
		SetDataFolder currentDF
		Abort "cropWaves: FileNameTruncated was not found in the current data folder."
	Endif

	//Determine if  "Crop" was checked
	controlInfo /W=zPhys_Settings check107
	Variable checknum107 = V_Value
	If(checknum107==1)
		tempnum1=1
	Else
		DoAlert 1, "Crop Waves?"
		tempnum1=V_flag
	Endif

	If (tempnum1==1)	//if cancel clicked on DoPrompt, then skip rest of proc


		Variable wavesHaveZeroTime = 1
		If (NVAR_Exists(f))
			wavesHaveZeroTime = f
		Elseif (NVAR_Exists(sweepTime))
			wavesHaveZeroTime = sweepTime
		Endif
		If (wavesHaveZeroTime == 0)
			DoAlert 1, "Must zero waves first."
			If (V_flag == 1)
				ZeroSweeps("ctrlName", 2)
			Else
				SetDataFolder currentDF
				Abort "Cropping aborted."
			Endif
		Endif

		////////////////////
		////////////////
		///////////////////
		//////////UPDATE THIS TO CROP WITH 2 CURSORS (left and right)
		Cursor /W=$ctrlName A, $inputname, leftx($inputname)
		Cursor /W=$ctrlName B, $inputname, rightx($inputname)

		/////////////////////////////
		Variable rval= UserCursorAdjust(ctrlName)
		if (rval == -1)							// Graph name error?
			DoWindow /K $ctrlName
			SetDataFolder currentDF
			Abort "Graph Error"
		endif

		if (rval == 1)								// User canceled?
			//DoAlert 0,"Canceled"
			DoWindow /K $ctrlName
			SetDataFolder currentDF
			Abort "User cancelled"
		endif
		//////////////////////////////

		For (i=tempwavenum1; i< tempwavenum2; i+=1)
			tempstring1 = FileNameTruncated+"_"+num2str(i)+input_type
			//cropstring= FileNameTruncated+"_"+num2str(i)+"_crop"
			//Duplicate /O /R=[hcsr(A),hcsr(B)] $tempstring1, $cropstring
			DeletePoints leftx($inputname),pcsr(A),$tempstring1
			DeletePoints pcsr(B),rightx($inputname), $tempstring1

		Endfor

		//Crop Stimulus trace
		Variable stimStartSweep = tempwavenum1
			If (NVAR_Exists(sweepStartnum))
				stimStartSweep = sweepStartnum
			Endif
			String stimwave = FileNameTruncated+"_"+num2str(stimStartSweep)+stim_type
		If (Exists(stimwave)==1)
			DoAlert 1, "Crop Stimulus Wave too?"
			If (V_flag==1)
				DeletePoints leftx($stimwave),pcsr(A),$stimwave
				DeletePoints pcsr(B),rightx($stimwave), $stimwave
			Endif
		Endif
		//String stimwavecrop = stimwave+"crop"
		//Duplicate /O /R=[hcsr(A),hcsr(B)] $stimwave $stimwavecrop
		//WAVE /Z wstimwavecrop = $stimwavecrop
		//SetScale /P X, 0, DimDelta(wStimwavetrim, 0), wstimwavecrop
		//Endif
		SetAxis/A
		SetDataFolder currentDF
	Endif
End

//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
// Manually changes a range of points in a selected wave; useful for stimulus repair/editing.
Function changeWavepoints(ctrlName): ButtonControl
	String ctrlName
	Variable i,j,n
	String inputwave
	Variable incrementVal=0
	Variable incrementNum=1
	Variable startpnt=3000
	Variable endpnt=3200
	Variable tempVal=1

	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
	Prompt startpnt, "Start point #:"
	Prompt endpnt, "End point #:"
	Prompt tempVal, "Change to value:"
	Prompt incrementVal, "Increment value (e.g., 6200):"
	Prompt incrementNum, "# times to increment:"
	DoPrompt "Select wave", inputwave,startpnt,endpnt,tempVal,incrementVal,incrementNum
	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		WAVE tempW = $inputwave

		For (n=0;n<incrementNum;n+=1)

			For (i = startpnt; i < endpnt; i += 1)
				j = (n * incrementVal) + i
				If (j >= 0 && j < numpnts(tempW))
					tempW[j] = tempVal
				Endif
			Endfor

		Endfor


	Endif

End


//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///

