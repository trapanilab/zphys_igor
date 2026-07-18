#pragma rtGlobals=3        // Full Igor Pro 9 cleanup version.
// Includes underscore naming v2 and zColor compile fix v4.
#include <Decimation>
#include <Waves Average>


// =================================================================================================
// JT zPhys event-analysis and spike-analysis helpers
// -------------------------------------------------------------------------------------------------
// Purpose:
//   Event detection, spike-time analysis, latency/amplitude summaries, vector strength analysis,
//   recurrence plots, and helper routines called by the JT_Controls panel and graph-control panels.
//
// Notes for maintenance:
//   * This file keeps the original public function names so existing panel buttons still work.
//   * The conservative patch keeps rtGlobals=1 because much of the original code relies on legacy
//     current-data-folder lookups and implicit globals. A separate rtGlobals=3 review copy is also
//     included for compile testing.
//   * Most generated waves are still written to root:A:Avg, root:A:Concat, or root:A:V, matching
//     the original workflow.
// =================================================================================================

////////////////////////////////////////////////////////////////////////////////////////////////////
//Find Peaks, calculate spike time, for JT_Controls panel
// Function: Find_Peaks
// Detect events/spikes from the JT_Controls panel using either cursor-delimited windows or full sweeps; creates spike-time, latency, amplitude, histogram, and per-sweep summary waves.
Function Find_Peaks(ctrlName): ButtonControl
	string ctrlName
	variable L_avg,L_cv,L_sem, L1_avg,L1_cv,L1_sem
	string tempfolder1
	variable baseval
	variable boxNum = 1
	variable tempwavenum1=1
	variable tempwavenum2=60
	variable adjustcurs
	variable wavenumber
	variable deltaXval
	variable pulselength

	variable i,j,k,m,n,z
	variable tempnum1,tempnum2,tempnum3,tempnum4
	Variable HistBins=40
	Variable templeftX,temprightX,tempMAXval,tempMINval
	Variable waveDelta
	Variable spikewidth
	
	String valAsStr,AMPavg
	String tempstring1a, tempstring1b, tempstring2a, tempstring2b,tempstring3a, tempstring3b,tempstring4,tempstringAMP,tempstringAMP1
	String accumwave1a, accumwave1b, accumwave2a, accumwave2b, accumwave3a, accumwave3b
	String STtemp,Ltemp,ST1temp,L1temp, EVENTtemp,AMPtemp, AMP1temp
	String AMP,ST, STsweep, STsweepSingle, L,EVENT
	String tempwave


	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwaveglobal = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type	

	NVAR tempfreq = root:A:tempfreq
	NVAR tempstep1 = root:A:tempstep1
	NVAR tempstep2 = root:A:tempstep2
	NVAR interval = root:A:interval
	NVAR dinterval = root:A:dinterval

	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR protocol = root:A:protocol
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent
	spikewidth = 2*spiketime
	
	NVAR /Z sweepTime
	SVAR /Z FileNameTruncated

	DFREF savedDF= GetDataFolderDFR()	// Save current data folder

	tempfolder1 = GetDataFolder(0)
	If (cmpstr (tempfolder1,"root")!=0)

		If (NVAR_exists(sweepTime)==0)
			DoAlert 0, "sweepTime was not found in this data folder. Continuing without zero-time check."
		ElseIf (sweepTime==0)
			DoAlert  1, "Must zero waves first"
			If (V_flag==1)
				Zerosweeps("ctrlName",2)
			Else
				Abort "User aborted."
			Endif
		Endif

	Endif

	//Determine if  "Multiple" is checked
	controlInfo /W=JT_Controls check201
	variable checknum201 = V_Value
	If(checknum201==1)

		tempwavenum1 = sweepStartnum
		tempwavenum2 = sweepEndnum
	Elseif (Exists ("sweepCurrent")==2)
		tempwavenum1 = sweepCurrent
		tempwavenum2 = sweepCurrent
	
	Else
		tempwavenum1 = 1
		tempwavenum2 = 1
	Endif

	variable checknum104, checknum105,checknum107,checknum108, checknum109

	//Determine if  "Detect 1st spike" was checked
	controlInfo /W=zPhys_Settings check108
	checknum108 = V_Value
		
	//Determine if  "Latency/period" was checked
	controlInfo /W=zPhys_Settings check104
	checknum104 = V_Value
				
		
	//Determine if  "Use cursors" was checked
	controlInfo /W=zPhys_Settings check105
	checknum105 = V_Value

	//Determine if  "Accumulate" was checked
	controlInfo /W=zPhys_Settings check109
	checknum109 = V_Value

	If((cmpstr(ctrlName,"adaptation")!=0)&&(cmpstr(ctrlName,"columns")!=0))  //skipping dialog for Dan Frolov and Sam Short experiments on Adaptation

		Prompt tempwavenum1, "First wave:"
		Prompt tempwavenum2, "Last wave:"
		Prompt boxNum, "Sliding Box #: (increase to 10 or 20 to smooth transients and artifacts)"
		Prompt tempnum1, "Create/Append histogram?" popup "No;Yes"
		DoPrompt "Detect Peaks From Multiple Waves", tempwavenum1, tempwavenum2	,boxNum,tempnum1
		tempwave = FileNameTruncated+input_type
	
	ElseIf (cmpstr(ctrlName,"columns")==0) //skipping dialog for Sam experiments on Adaptation
		Setdatafolder root:A:Avg

		String listofWaves = wavelist ("*",";","") //list of all Adc-1 waves in current folder
		If (cmpstr(listofWaves,"")==0)
			Abort ("No waves found")
		Endif	

		Prompt tempwave, "Select wave", popup (listofWaves)
		DoPrompt "Load Column wave", tempwave
					
		tempwavenum1 = 1
		tempwavenum2 = DimSize ($tempwave,1)
		//Print tempwavenum2
		
		If (tempwavenum2==0)
			Setdatafolder savedDF
			Abort "Only one column!"
		Endif

		
	ElseIf (cmpstr(ctrlName,"adaptation")==0) //skipping dialog for Dan experiments on Adaptation
		Variable tempinterval = interval
		Variable temptempstep1 = tempstep1
		Prompt tempinterval, "Set interval (s):"
		Prompt temptempstep1, "Set Step1 (s):"		
		DoPrompt "Detect Peaks From Multiple Waves", tempinterval, temptempstep1
		tempwave = FileNameTruncated+input_type
		interval = tempinterval
		tempstep1 = temptempstep1
	Endif
	
	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		
		Plot_Waves (tempwave,tempwavenum1,tempwavenum2)
		
		//get wave and graphname
		String topWave = wavename("",0,1)
		String topGraph = WinName(0, 1)	// Name of top graph
				
		//Setup notebook for storing info
		String nb0 = "Statistics"
		String nb_list=WinList(nb0,";","WIN:16")
		If (cmpstr(nb_list,"")==0)
			NewNotebook/N=$nb0 /F=0/V=1/K=2 /W=(20,20,380,580)
			DoWindow /B=$topGraph $nb0

		Endif
		Notebook $nb0 defaultTab=20, statusWidth=252
		Notebook $nb0 font="Geneva", fSize=10, fStyle=0, textRGB=(0,0,0), selection={endOfFile, endOfFile}

			
		//Determine if SpikePerSweep_histgraph is present
		String SpikeperSweep_histgraph = "HistSpikePerSweep"
		tempnum4=0
		string histgraphs=WinList(SpikeperSweep_histgraph,";","WIN:1") // A list of all graphs with name SpikeperSweepAccum_graph
		If (cmpstr(histgraphs,"")!=0)
			tempnum4=1
		Endif	
			
		
		//Add Stimulus trace	
		String stimwave = FileNameTruncated+"_"+num2str(tempwavenum1)+stim_type
		If (Exists(stimwave)==1)
			string traces=TraceNameList(topGraph,";",1)
			string tracematch = listmatch(traces,stimwave)
			If(cmpstr(tracematch,"")==0) // Assumes that each wave is plotted at most once on a graph. 
				AppendtoGraph /W=$topGraph /R=right $stimwave
				ModifyGraph rgb($stimwave)=(34952,34952,34952)
			Endif
		Endif
		
		DoUpdate

		//Determine if  "Crop" was checked
		controlInfo /W=zPhys_Settings check107
		checknum107 = V_Value
		If(checknum107==1)
			cropWaves(topGraph,tempwavenum1,tempwavenum2)
		Endif
	
		//Determine if "Cursors" was checked		
		If (checknum105==1)
			
			variable startXval = 0.15 //150 ms is our current stim start time
			variable cursornum = 2
			If (protocol==1)
				//cursornum = round (1 + (0.2/tempstep1)) //200 ms is the length of stimulus we use currently
			Elseif (protocol==2)
				cursornum = round (1 + (0.2/(1/tempfreq))) //200 ms is the length of stimulus we use currently
			Elseif (protocol==3)
				cursornum = 4
			Endif
			
			If(cmpstr(ctrlName,"adaptation")!=0) //skipping dialog for Dan Frolov experiments on Adaptation
				Prompt startXval, "First cursor X value (s):"
				Prompt adjustcurs, "Adjust cursors first?" popup "No;Yes"
				Prompt cursornum, "Number of cursors:"
				If (checknum109==0)
					Prompt tempnum3, "Accumulate spike times?" popup "No;Yes"
				Else
					Prompt tempnum3, "Accumulate spike times?" popup "Yes;No"
				Endif
				DoPrompt "Set Graph Cursors", startXval,cursornum,adjustcurs,tempnum3
			Else  //skipping dialog for Dan Frolov experiments on Adaptation
				startXval=0.15
				tempnum3=1
				V_flag=0
			Endif

			If (checknum109==1&&tempnum3==1)
				tempnum3=2
			Elseif(checknum109==1&&tempnum3==2)
				tempnum3=1
			Endif
			
			//make odd number of cursors for analysis
			//			Variable cursornumcheck1 = cursornum/2
			//			Variable cursornumcheck2 = cursornumcheck1 - floor(cursornumcheck1)
			//			If (cursornumcheck2==0 )
			//				cursornum = cursornum+1
			//			Endif
			
			
			If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
				DoWindow /K $topGraph
				Setdatafolder savedDF
				Abort "User canceled"
			Endif


			//Protocol to analyze spikes
			If (protocol==2) //frequency
				deltaXval = 1/tempfreq //time in seconds
			Else //pairs //steps or pairs
				deltaXval = tempstep1			
				// need to fix for tempstep2
			Endif

			If (tempnum4==1&&tempnum1==2)
				Prompt tempnum2, "Overwrite histogram?" popup "No;Yes"
				Prompt HistBins, "Number of bins:"
				DoPrompt "Create spike time histogram",HistBins,tempnum2
			ElseIf (tempnum1==2)
				Prompt HistBins, "Number of bins:"
				DoPrompt "Create spike time histogram",HistBins
				tempnum2=2
			Endif
			If (V_flag!=0)	//if cancel clicked on DoPrompt
				tempnum1=1
			Endif			

			
			//ADD CURSORS TO GRAPH
			Variable rval2
			If (Exists(stimwave)==1)
				rval2 = AddCursorsToGraph(topGraph,cursornum,stimwave,startXval,deltaXval,protocol)
			Else //Add cursors to graph as free cursors		
				rval2 = AddCursorsToGraph(topGraph,cursornum,topwave,startXval,deltaXval,protocol)
			Endif
			If (rval2 == 0)
				KillWindow $topGraph
				Setdatafolder savedDF

				Abort "Bad value for number of cursors!"
			Elseif(rval2 == -1)
				KillWindow $topGraph
				Setdatafolder savedDF

				Abort "Bad value for First cursor X value!"
			Elseif(rval2 == -2)
				KillWindow $topGraph
				Setdatafolder savedDF

				Abort "Bad value for cursor spacing!"
			Else
				cursornum = rval2 //change the cursornum variable to the value returned by AddCursorsToGraph
			Endif
			
			
			//Adjust Cursors
			If (adjustcurs==2)
				Showinfo
				Variable rval1= UserCursorAdjust(topGraph)
				if (rval1 == -1)							// Graph name error?
					KillWindow $topGraph
					Setdatafolder savedDF

					Abort "No such graph."
				elseif (rval1 == 1)								// User canceled?
					KillWindow $topGraph
					Setdatafolder savedDF

					Abort
				endif
			Endif

			String cursorNames = "ABCDEFGHIJ"
			Variable leftnum,rightnum,leftcsr,rightcsr
			
			leftcsr = hcsr($(cursorNames[n]))
			If (cursornum==1) //Add a cursor to the graph at the very end
				rightcsr = DimSize($topwave,0)*DimDelta($topwave,0)
				Cursor /H=2 /S=1 /C=(65535,0,0) /W=$(topGraph) $(cursorNames[cursornum]) $(topwave), rightcsr
				cursornum=2	
			Else	
				rightcsr = hcsr($(cursorNames[cursornum-1]))
			Endif
						
			Notebook $nb0 text="\r\r"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"\r"
			
			If(checknum108==1)
				Notebook $nb0 text="Note: a separate wave with only first events was created.\r"
			Endif
			
			AMPtemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMPtemp"
			STtemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_STtemp"
			Ltemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_Ltemp"
			AMP1temp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP1temp"
			ST1temp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1temp"
			L1temp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L1temp"
			wavenumber = tempwavenum2-tempwavenum1+1
	
			//Trim the stimulus file for the ST graphs
			If (Exists(stimwave)==1)
				String stimwavetrim = stimwave+"_trim"
				Duplicate /O /R=(leftcsr,rightcsr) $stimwave $stimwavetrim
				WAVE /Z wStimwavetrim = $stimwavetrim
				SetScale /P X, 0, DimDelta(wStimwavetrim, 0), wStimwavetrim  //leftx,rightx
			Endif
		
			//Determine if SpikePerSweepAccum_graph is present
			If (tempnum3==2)
				String SpikeperSweepAccum_graph = "SpikePerSweepAccum"
				string spikegraphs=WinList(SpikeperSweepAccum_graph,";","WIN:1") // A list of all graphs with name SpikeperSweepAccum_graph
				If (cmpstr(spikegraphs,"")==0)
					tempnum3=3
				Endif
			Endif	
			
			String SpikeperSweep_graph = "SpikePerSweep_"+FileNameTruncated
			DoWindow /Z /K $(SpikeperSweep_graph)


			For (n=0; n<cursornum-1; n+=1)
				//create temp strings    ******* (removed: +"_"+num2str(tempwavenum1)+)******
				tempstringAMP = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP_"+cursorNames[n]+cursorNames[n+1]
				tempstringAMP1 = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP1_"+cursorNames[n]+cursorNames[n+1]
				tempstring1a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST_"+cursorNames[n]+cursorNames[n+1]
				tempstring1b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1_"+cursorNames[n]+cursorNames[n+1]
				tempstring2a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L_"+cursorNames[n]+cursorNames[n+1]
				tempstring2b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L1_"+cursorNames[n]+cursorNames[n+1]
				tempstring3a = tempstring1a+"_swp"
				tempstring3b = tempstring1b+"_swp"

				string spikeaccumtraces, spikeaccumtracematch
			
				If (checknum108==1)
					//Determine if Wave was already loaded and delete it before renaming incoming wave
					If (WaveExists($tempstring3b)==1&&tempnum3==3)  //Close embeded graph in order to killwaves
						spikeaccumtraces=TraceNameList(SpikeperSweepAccum_graph,";",1)
						spikeaccumtracematch = listmatch(spikeaccumtraces,tempstring3b)  //Added the single quotes to delineate a X vs Y trace
						If(cmpstr(spikeaccumtracematch,"")!=0) // Assumes that each wave is plotted at most once on a graph. 
							RemoveFromGraph /W=$SpikeperSweepAccum_graph $(tempstring3b) //Added the single quotes to delineate a X vs Y trace
						Endif
					Endif
					Killwaves /Z $(tempstring1b)
					Killwaves /Z $(tempstring3b)
					Make /O /N=0 $tempstring3b = 0
				Endif
				
				
				//Determine if Wave was already loaded and delete it before renaming incoming wave
				If (WaveExists($tempstring3a)==1&&tempnum3==3)  //Close embeded graph in order to killwaves
					spikeaccumtraces=TraceNameList(SpikeperSweepAccum_graph,";",1)
					spikeaccumtracematch = listmatch(spikeaccumtraces,tempstring3a)  //Added the single quotes to delineate a X vs Y trace
					If(cmpstr(spikeaccumtracematch,"")!=0) // Assumes that each wave is plotted at most once on a graph. 
						RemoveFromGraph /W=$SpikeperSweepAccum_graph $(tempstring3a) //Added the single quotes to delineate a X vs Y trace
					Endif
				Endif
				Killwaves /Z $(tempstringAMP)
				Killwaves /Z $(tempstringAMP1)
				Killwaves /Z $(tempstring1a)
				Killwaves /Z $(tempstring2a)
				Killwaves /Z $(tempstring2b)
				Killwaves /Z $(tempstring3a)
				Make /O /N=0 $tempstring3a = 0
			Endfor
					
			//Detect Events
			Variable newWaveNumPoints
			Variable WaveNumPoints
			Variable spiketotal1a=0
			Variable spiketotal1b=0
			
			WAVE /Z temp2DWave = $(tempwave)
			If (WaveExists(temp2DWave)==0)
				Setdatafolder savedDF
				Abort "Input 2D wave not found: "+tempwave
			Endif
			waveDelta = DimDelta(temp2DWave, 0 )
			spikewidth = 2*spiketime
				
			For (i=tempwavenum1-1; i< tempwavenum2; i+=1)
				
				//parse out one wave at a time from the 2D wave in order to use FindLevels
				MatrixOP/FREE wTemp = col(temp2DWave, i)
				SetScale /P x 0,waveDelta,"s", wTemp



				For (n=0; n<cursornum-1; n+=1) //standard cursor incrementing
				
					tempstringAMP = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP_"+cursorNames[n]+cursorNames[n+1]
					tempstringAMP1 = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP1_"+cursorNames[n]+cursorNames[n+1]
					tempstring1a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST_"+cursorNames[n]+cursorNames[n+1]
					tempstring1b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1_"+cursorNames[n]+cursorNames[n+1]
					tempstring2a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L_"+cursorNames[n]+cursorNames[n+1]
					tempstring2b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L1_"+cursorNames[n]+cursorNames[n+1]
					tempstring3a = tempstring1a+"_swp"
					tempstring3b = tempstring1b+"_swp"

					//Skip B-C cursor pairs
					If ((protocol==3)&&(n==2))
						//iterate the C-D cursor pair by the delta interval that increases with each sweep (unless dInterval=0)
						leftnum = (dInterval*(i)/waveDelta)+pcsr($(cursorNames[n])) //(interval/waveDelta)+
						rightnum = (dInterval*(i)/waveDelta)+pcsr($(cursorNames[n+1])) //removed (interval/waveDelta)+
					
					Else
					
						leftnum = pcsr($(cursorNames[n]))
						rightnum = pcsr($(cursorNames[n+1]))
					
					Endif
					

					//Determine Latency1 if "1 event per period" checked
					If ((checknum104==1)&&(checknum108==1))
						FindLevel /Q /B=(boxNum) /EDGE=2 /P /R=[leftnum,rightnum] wTemp eventamp
						If (V_flag==0) //If cursors checked then subtract first cursor location
							Make /O /N=1 $L1temp = (V_LevelX-leftnum)
							concatenate /NP /KILL {$(L1temp)}, $(tempstring2b)
						Endif
					Endif						
			
					//Determine ST1 if "single event per period" is checked
					If (checknum108==1)
						FindLevel /Q /B=(boxNum) /EDGE=2 /P /R=[leftnum,rightnum] wTemp eventamp
						If (V_flag==0)
							Make /O /N=1 $ST1temp = V_LevelX
							WAVE STtempWave1 = $(ST1temp)
							newWaveNumPoints=numpnts($ST1temp)

							Make /O /N=(newWaveNumPoints) $AMP1temp
							WAVE AMPtempWave1 = $(AMP1temp)
					
							For (k=0;k<newWaveNumPoints;k+=1)
								templeftX = pnt2x(wTemp,STtempWave1[k])
								temprightX = pnt2x(wTemp,STtempWave1[k])+(2*spikewidth)

								tempMAXval = wavemax (wTemp, templeftX,temprightX) //V_PeakVal
								tempMINval = wavemin (wTemp, templeftX,temprightX) //V_PeakVal
								AMPtempWave1[k] = abs(tempMAXval)+abs(tempMINval)
							Endfor
	
							concatenate /NP /KILL {$(AMP1temp)}, $(tempstringAMP1)					
							concatenate /NP /KILL {$(ST1temp)}, $(tempstring1b)
						Else
							newWaveNumPoints=0 //reset incase the above assigment doesn't happen (i.e., checknum108==0)
						Endif
						
						//Count the number of events per sweep
						WAVE wSTcountb=$(tempstring3b)
						WaveNumPoints = numpnts($tempstring3b)
						InsertPoints /M=0 WaveNumPoints, newWaveNumPoints, wSTcountb
						For (m=0; m<newWaveNumPoints; m+= 1)
							wSTcountb[WaveNumPoints+m] = i
						Endfor
					Endif

					//Determine LATENCY
					If (checknum104==1)//&&(checknum108==0)
						FindLevels /Q /B=(boxNum) /DEST=$(Ltemp) /EDGE=2 /M=(spikewidth) /P /R=[leftnum,rightnum] wTemp eventamp
						Wave wLtemp = $(Ltemp)
						wLtemp[p] = wLtemp[p]-leftnum
						concatenate /NP /KILL {$(Ltemp)}, $(tempstring2a)
					Endif	

					//Determine ST for all events inbetween cursors n and n+1				
					FindLevels /Q /B=(boxNum) /DEST=$(STtemp) /EDGE=2 /M=(spikewidth) /P /R=[leftnum,rightnum] wTemp eventamp //
					WAVE STtempWave = $(STtemp)
					newWaveNumPoints=numpnts(STtempWave)
					Make /O /N=(newWaveNumPoints) $AMPtemp
					WAVE AMPtempWave = $(AMPtemp)
					
					//Determine amplitude of spikes
					For (k=0;k<newWaveNumPoints;k+=1)
						templeftX = pnt2x(wTemp,STtempWave[k])
						temprightX = pnt2x(wTemp,STtempWave[k])+(2*spikewidth)
						tempMAXval = wavemax (wTemp, templeftX,temprightX)
						tempMINval = wavemin (wTemp, templeftX,temprightX)
						AMPtempWave[k] =abs(tempMAXval)+abs(tempMINval)
					Endfor
					
					concatenate /NP /KILL {$(AMPtemp)}, $(tempstringAMP)					
					concatenate /NP /KILL {$(STtemp)}, $(tempstring1a)
					
					//Count the number of events per sweep
					WAVE wSTcounta=$(tempstring3a)
					WaveNumPoints = numpnts($tempstring3a)
					InsertPoints /M=0 WaveNumPoints, newWaveNumPoints, wSTcounta
					For (m=0; m<newWaveNumPoints; m+= 1)
						wSTcounta[WaveNumPoints+m] = i
					Endfor
					
					If (protocol==3)
						n+=1 //increment n for the pairs
					Endif
				Endfor //For loop for cursor pairs
			Endfor //For loop for sweeps
			

			
			//Calculate and print values for detected events
			For (n=0; n<cursornum-1; n+=1)
				tempstringAMP = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP_"+cursorNames[n]+cursorNames[n+1]
				tempstring1a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST_"+cursorNames[n]+cursorNames[n+1]
				tempstring1b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1_"+cursorNames[n]+cursorNames[n+1]
				tempstring2a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L_"+cursorNames[n]+cursorNames[n+1]
				tempstring2b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L1_"+cursorNames[n]+cursorNames[n+1]
				tempstring3a = tempstring1a+"_swp"
				tempstring3b = tempstring1b+"_swp"
				tempstring4 = "root:A:Avg:spikehistogram"+cursorNames[n]+cursorNames[n+1]

				//SCALE the Latency and Spike Time waves (the stimtrim trace is scaled too!!!)
				If(checknum108==1)
					WAVE /Z wSTb = $(tempstring1b)
					WAVE /Z wLb = $(tempstring2b)
					wSTb=(waveDelta*wSTb)
					wLb=(waveDelta*wLb)
				Endif
				
				WAVE /Z wSTa = $(tempstring1a)
				WAVE /Z wLa = $(tempstring2a)
				wSTa=(waveDelta*wSTa)
				wLa=(waveDelta*wLa)
				
				//Setup for HISTOGRAM
				Variable deltaxhist
				deltaxhist = hcsr($(cursorNames[n+1]),topGraph)-hcsr($(cursorNames[n]),topGraph)
								
				//HISTOGRAM of the spikes for each cursor pair.
				// When "Detect 1st spike" is off, use the all-event spike-time wave.
				String histSourceWave = tempstring1a
				If (checknum108==1)
					histSourceWave = tempstring1b
				Endif
				If ((tempnum1==2)&&(Exists(histSourceWave)==1))
					If ((tempnum4==0)||(tempnum2==2))
						Make /O /N=(HistBins) $tempstring4
						SetScale /P X (n*deltaxhist),(deltaxhist/HistBins), $tempstring4
						Histogram /B=2 /C $(histSourceWave),$tempstring4
					Else
						Histogram /A /B=2 /C $(histSourceWave),$tempstring4
					Endif
				Endif
				

				//Determine if  "Latency" and "1 event per period" were checked
				//calculate mean Latency for all spikes

				If (checknum104==1) //&&(checknum108==0)) //"1 event per period" NOT checked
					If (numpnts(wLa)>0)
						wavestats /Q wLa
						sprintf valAsStr, "%.3g", V_avg
						L_avg= str2num(valAsStr)
						
						sprintf valAsStr, "%.3g", V_sem
						L_sem= str2num(valAsStr)						
						
						sprintf valAsStr, "%.3g", (V_sdev/V_avg)
						L_cv= str2num(valAsStr)
					Endif
				Endif

				//Determine if  "Latency" and "1 event per period" were checked
				//calculate mean first spike Latency 
				variable pointnumber
				If ((checknum104==1)&&(checknum108==1))
					If (numpnts(wLb)>0)
						wavestats /Q wLb
						sprintf valAsStr, "%.3g", V_avg
						L1_avg= str2num(valAsStr)
						
						sprintf valAsStr, "%.3g", V_sem
						L1_sem= str2num(valAsStr)					
						
						sprintf valAsStr, "%.3g", (V_sdev/V_avg)
						L1_cv= str2num(valAsStr)
					Endif
				Endif	
					

				
				//If accum was checked, then accumulate the latency values for cursors in the A folder
				//Add each sweep to the accumulating tables ** in the future, determine if rewrite the table or append for now use If, then statement below
				If (tempnum3>1) 
					//Make the spike number waves
					accumwave1a = "root:A:Avg:totalSpikeCount_"+cursorNames[n]+cursorNames[n+1]
					String wName1a = "root:A:Avg:totalSpikeCount_names"
						
					If (Exists(accumwave1a)==0)
						Make /O /N=(0) $accumwave1a
					Endif
					If (Exists(wName1a)==0)
						Make/N=(cursornum-1)/T $wName1a
					Endif
		
					WAVE wAccum1a=$(accumwave1a)
					WAVE /T wN1a = $wName1a

					//Count the number of spikes in the Total accum wave
					Variable accumWavepoints = numpnts($accumwave1a)
					InsertPoints /M=0 accumWavepoints, 1, wAccum1a //add a slot for the new latency value
					wAccum1a[accumWavepoints]= numpnts($tempstring1a)

					//Make the Latencies wave
					accumwave2a= "root:A:Avg:totalSpikeLatencies_"+cursorNames[n]+cursorNames[n+1]
					String wName2a = "root:A:Avg:totalSpikeLatency_names"
				
					If (Exists(accumwave2a)==0)
						Make /O /N=(0) $accumwave2a
					Endif					
					If (Exists(wName2a)==0)
						Make/N=(cursornum-1)/T $wName2a
					Endif
					WAVE wAccum2a=$(accumwave2a)
					WAVE /T wN2a = $wName2a

					//Count the number of values in the Latency accum wave
					InsertPoints /M=0 accumWavepoints, 1, wAccum2a //add a slot for the new latency value
					wAccum2a[accumWavepoints]=L_avg

					//Make the CVs wave
					accumwave3a= "root:A:Avg:totalSpikeCVs_"+cursorNames[n]+cursorNames[n+1]
					String wName3a = "root:A:Avg:totalSpikeCV_names"
				
					If (Exists(accumwave3a)==0)
						Make /O /N=(0) $accumwave3a
					Endif					
					If (Exists(wName3a)==0)
						Make/N=(cursornum-1)/T $wName3a
					Endif
					WAVE wAccum3a=$(accumwave3a)
					WAVE /T wN3a = $wName3a

					//Count the number of values in the CV accum wave
					InsertPoints /M=0 accumWavepoints, 1, wAccum3a //add a slot for the new latency value
					wAccum3a[accumWavepoints]=L_cv


					///////
					///////
					//Make latency and spike number wave for "First only"
					If (checknum108==1)
						//Make the 1st spike number wave
						accumwave1b = "root:A:Avg:firstSpikeCount_"+cursorNames[n]+cursorNames[n+1]
						String wName1b = "root:A:Avg:firstSpikeCount_names"

						If (Exists(accumwave1b)==0)
							Make /O /N=(0) $accumwave1b
						Endif
						If (Exists(wName1b)==0)
							Make/N=(cursornum-1)/T $wName1b
						Endif	
						WAVE wAccum1b=$(accumwave1b)
						WAVE /T wN1b = $wName1b
		
						//Count the number of spikes in the First accum wave
						InsertPoints /M=0 accumWavepoints, 1, wAccum1b //add a slot for the new latency value
						wAccum1b[accumWavepoints]= numpnts($tempstring1b)
					
					
						//Make the Latencies wave
						accumwave2b= "root:A:Avg:firstSpikeLatencies_"+cursorNames[n]+cursorNames[n+1]
						String wName2b = "root:A:Avg:firstSpikeLatency_names"

						If (Exists(accumwave2b)==0)
							Make /O /N=(0) $accumwave2b
						Endif
						If (Exists(wName2b)==0)
							Make/N=(cursornum-1)/T $wName2b
						Endif
						WAVE wAccum2b=$(accumwave2b)
						WAVE /T wN2b = $wName2b

						//Count the number of values in the Latency accum wave
						InsertPoints /M=0 accumWavepoints, 1, wAccum2b //add a slot for the new latency value
						wAccum2b[accumWavepoints]=L1_avg
		
		
						//Make the CVs wave
						accumwave3b= "root:A:Avg:firstSpikeCVs_"+cursorNames[n]+cursorNames[n+1]
						String wName3b = "root:A:Avg:firstSpikeCV_names"

						If (Exists(accumwave3b)==0)
							Make /O /N=(0) $accumwave3b
						Endif
						If (Exists(wName3b)==0)
							Make/N=(cursornum-1)/T $wName3b
						Endif
						WAVE wAccum3b=$(accumwave3b)
						WAVE /T wN3b = $wName3b

						//Count the number of values in the CV accum wave
						InsertPoints /M=0 accumWavepoints, 1, wAccum3b //add a slot for the new latency value
						wAccum3b[accumWavepoints]=L1_cv
		

					Endif

				Endif //end the accumulation portion
					

				If (checknum104==1)
					Notebook $nb0 text="Avg latency for all spikes = "+num2str(L_avg)+" ± "+num2str(L_sem)+" SEM s; with a "+num2str(L_cv)+" CV for cursor"+cursorNames[n]+" @ "+num2str(hcsr($(cursorNames[n]),topGraph))+" s)\r"
				Endif
				
				If ((checknum104==1)&&(checknum108==1)) //"1 event per period" is checked
					Notebook $nb0 text="FSL = "+num2str(L1_avg)+" ± "+num2str(L1_sem)+" SEM s; with "+num2str(L1_cv)+" CV for cursor"+cursorNames[n]+" @ "+num2str(hcsr($(cursorNames[n]),topGraph))+" s)\r"
				Endif
				
				
				//Tally the events in each of the cursor pairs				
				spiketotal1a +=numpnts($tempstring1a )
				If(checknum108==1)
					spiketotal1b +=numpnts($tempstring1b)
				Endif
				
				If (protocol==3)
					n+=1 //increment n for the pairs
				Endif
			Endfor
			
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			//@#$%^&*()(*&^%$#@#$%^&*()*&^%$#@#$%^&*&^%$#@#$%^&*()
			
			//Graph the spike times
			For (n=0; n<cursornum-1; n+=1)
				accumwave3a= "root:A:Avg:totalSpikeCVs_"+cursorNames[n]+cursorNames[n+1]
				accumwave3b= "root:A:Avg:firstSpikeCVs_"+cursorNames[n]+cursorNames[n+1]
				accumwave2a= "root:A:Avg:totalSpikeLatencies_"+cursorNames[n]+cursorNames[n+1]
				accumwave2b= "root:A:Avg:firstSpikeLatencies_"+cursorNames[n]+cursorNames[n+1]
				accumwave1a = "root:A:Avg:totalSpikeCount_"+cursorNames[n]+cursorNames[n+1]
				accumwave1b = "root:A:Avg:firstSpikeCount_"+cursorNames[n]+cursorNames[n+1]

				
				tempstringAMP = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP_"+cursorNames[n]+cursorNames[n+1]
				tempstring1a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST_"+cursorNames[n]+cursorNames[n+1]
				tempstring1b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1_"+cursorNames[n]+cursorNames[n+1]
				tempstring2a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L_"+cursorNames[n]+cursorNames[n+1]
				tempstring2b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L1_"+cursorNames[n]+cursorNames[n+1]
				tempstring3a = tempstring1a+"_swp"
				tempstring3b = tempstring1b+"_swp"
				tempstring4 = "root:A:Avg:spikehistogram"+cursorNames[n]+cursorNames[n+1]
			
				//calculate mean AMP, ignoring NaNs without mutating the source amplitude wave
				String tempAMPwave = "tempAMPwave"
				variable AMP_avg = NaN
				If ((Exists(tempstringAMP)==1)&&(numpnts($tempstringAMP)>0))
					Duplicate /O $tempstringAMP $tempAMPwave
					WaveTransform /O ZapNaNs $tempAMPwave
					If (numpnts($tempAMPwave)>0)
						AMP_avg = mean($tempAMPwave)*1e12 //convert to picoAmps
						sprintf valAsStr, "%.3g", AMP_avg
						AMP_avg= str2num(valAsStr)
					Endif
					Killwaves /Z $tempAMPwave
				Endif
							
				If ((n==0)&&(WaveExists($tempstring1a)==0))
					If (tempnum3==3)  //Add each sweep to the accumulating graph
						Display /N=$(SpikeperSweepAccum_graph) /W=(900,50,1400,250 ) /K=1
					Endif
					//Make blank graph
					Display /N=$(SpikeperSweep_graph) /W=(900,50,1400,250 ) /K=1
					TextBox /W=$topGraph /A=LT /N=textbox1 /X=0 /Y=-3 /F=0 "\\Z10"+num2str(numpnts($tempstring1a ))+" events ("+cursorNames[n]+"to"+cursorNames[n+1]+")\r"		
				
				ElseIf ((n==0)&&(WaveExists($tempstring1a)==1))
					If (tempnum3==3)  //Add each sweep to the accumulating graph
						Display /N=$(SpikeperSweepAccum_graph) /W=(900,50,1400,250 ) /K=1 $tempstring3a vs $tempstring1a
						ModifyGraph /W=$(SpikeperSweepAccum_graph) mode($tempstring3a)=3,marker($tempstring3a)=19,mSize($tempstring3a)=1, useMrkStrokeRGB($tempstring3a)=1,MrkStrokeRGB($tempstring3a)=(52428,1,1),mrkThick($tempstring3a)=1, rgb($tempstring3a)=(0,0,0)

					Elseif (tempnum3==2) //Append to the preexisting graph
						AppendtoGraph /W=$(SpikeperSweepAccum_graph) $(tempstring3a) vs $(tempstring1a)
						ModifyGraph /W=$(SpikeperSweepAccum_graph) mode($tempstring3a)=3,marker($tempstring3a)=19,mSize($tempstring3a)=1, useMrkStrokeRGB($tempstring3a)=1,MrkStrokeRGB($tempstring3a)=(52428,1,1),mrkThick($tempstring3a)=1,rgb($tempstring3a)=(0,0,0)
					Endif				
					
					//Add each sweep to graph
					Display /N=$(SpikeperSweep_graph) /W=(900,50,1400,250 ) /K=1 $tempstring3a vs $tempstring1a
					
					If (checkNum104==0) //Don't print if Latency checked since it includes spike number
						Notebook $nb0 text=num2str(numpnts($tempstring1a ))+" events ("+cursorNames[n]+"to"+cursorNames[n+1]+")\r"
					Endif
					TextBox /W=$topGraph /A=LT /N=textbox1 /X=0 /Y=-3 /F=0 "\\Z10"+num2str(numpnts($tempstring1a ))+" events ("+cursorNames[n]+"to"+cursorNames[n+1]+") | mean spike = "+num2str(AMP_avg)+" pA\r"	


				Elseif (WaveExists($tempstring1a)==1)
					If(tempnum3>1)
						AppendtoGraph /W=$(SpikeperSweepAccum_graph) $tempstring3a vs $tempstring1a
						ModifyGraph /W=$(SpikeperSweepAccum_graph) mode($tempstring3a)=3,marker($tempstring3a)=19,mSize($tempstring3a)=1, useMrkStrokeRGB($tempstring3a)=1,MrkStrokeRGB($tempstring3a)=(52428,1,1),mrkThick($tempstring3a)=1,rgb($tempstring3a)=(0,0,0)
					Endif

					AppendtoGraph /W=$(SpikeperSweep_graph) $(tempstring3a) vs $(tempstring1a)

					If (checkNum104==0) //Don't print if Latency checked since it includes spike number
						Notebook $nb0 text=num2str(numpnts($tempstring1a ))+" events ("+cursorNames[n]+"to"+cursorNames[n+1]+")\r"
					Endif
					AppendText /W=$topGraph /N=textbox1 "\\Z10"+num2str(numpnts($tempstring1a ))+" events ("+cursorNames[n]+"to"+cursorNames[n+1]+") | mean spike = "+num2str(AMP_avg)+" pA\r"
				Endif


				//Make a table of the Latencies and Spike numbers
				If (tempnum3>1&&(n==0)&&(WaveExists($tempstring1a)==1))

					wN1a[n] = nameofwave($accumwave1a)
					wN2a[n] = nameofwave($accumwave2a)
					wN3a[n] = nameofwave($accumwave3a)
					
					Edit /K=1 /N=TotalSpikes $(accumwave1a) as "Total Spike Count"
					Edit /K=1 /N=TotalLatencies $(accumwave2a) as "Total Spike Latencies"
					Edit /K=1 /N=TotalCVs $(accumwave3a) as "Total CVs"
					
					If (checknum108==1)

					
						wN1b[n] = nameofwave($accumwave1b)
						wN2b[n] = nameofwave($accumwave2b)
						wN3b[n] = nameofwave($accumwave3b)
						
						
						Edit /K=1 /N=FirstSpikes $(accumwave1b) as "First Spike Count"
						Edit /K=1 /N=FirstSpikeLatencies $(accumwave2b) as "Mean First Spike Latencies"
						Edit /K=1 /N=FirstSpikeCVs $(accumwave3b) as "Mean First Spike CVs"
					Endif
					
				Elseif (tempnum3>1&&(WaveExists($tempstring1a)==1))
					AppendtoTable /W=TotalSPikes $(accumwave1a)
					AppendtoTable /W=TotalLatencies $(accumwave2a)
					AppendtoTable /W=TotalCVs $(accumwave3a)
					wN1a[n] = nameofwave($accumwave1a)
					wN2a[n] = nameofwave($accumwave2a)
					wN3a[n] = nameofwave($accumwave3a)
					
					If (checknum108==1)
						AppendtoTable /W=FirstSpikes $(accumwave1b)
						AppendtoTable /W=FirstSpikeLatencies $(accumwave2b)
						AppendtoTable /W=FirstSpikeCVs $(accumwave3b)
						wN1b[n] = nameofwave($accumwave1b)
						wN2b[n] = nameofwave($accumwave2b)
						wN3b[n] = nameofwave($accumwave3b)
					Endif			
				Endif

				If (protocol==3)
					n+=1 //increment n for the pairs
				Endif
			Endfor //end making graphs

			//Modify Accum graph graph
			If (tempnum3==3||(tempnum3==2))
				ModifyGraph /W=$(SpikeperSweepAccum_graph) nticks(bottom)=10,minor(bottom)=1,sep(bottom)=1, tick(left)=3
				SetAxis /W=$(SpikeperSweepAccum_graph) /A/N=0/E=0 bottom //DimOffset($stimwavetrim,0), (DimSize($stimwavetrim,0)*DimDelta($stimwavetrim,0))
				SetAxis /W=$(SpikeperSweepAccum_graph) /A/N=1/E=1 left
				Label /W=$(SpikeperSweepAccum_graph) Left "Sweep (#)"
				Label /W=$(SpikeperSweepAccum_graph) bottom "Time (s)"
						
				//Append Stim Graph
				If (Exists(stimwave)==1)
					AppendtoGraph /W=$(SpikeperSweepAccum_graph) /R=right $stimwavetrim
					ModifyGraph  /W=$(SpikeperSweepAccum_graph) rgb($stimwavetrim)=(34952,34952,34952)
					ModifyGraph  /W=$(SpikeperSweepAccum_graph)  tick(right)=3,noLabel(right)=2
				Endif
				
				//Graph_Panel(SpikeperSweepAccum_graph) //Display Graph Panel
			Endif
			

			//Modify the spike time Graphs
			For (n=0; n<cursornum-1; n+=1)
				tempstring1a = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST_"+cursorNames[n]+cursorNames[n+1]
				tempstring1b = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST1_"+cursorNames[n]+cursorNames[n+1]
				tempstring3a = tempstring1a+"_swp"
				tempstring3b = tempstring1b+"_swp"

				If (checknum108==1)
					If ((Exists(tempstring1b)==1)&&(Exists(tempstring3b)==1))
						AppendtoGraph /W=$(SpikeperSweep_graph) $(tempstring3b) vs $(tempstring1b)
						ModifyGraph /W=$(SpikeperSweep_graph) rgb($tempstring3b)=(65535,0,0)
					Endif
				Endif
			
				//Modify individual graphs
				ModifyGraph /W=$(SpikeperSweep_graph)mode=3,msize=3,marker=19, useMrkStrokeRGB=1,mrkThick=1,mrkStrokeRGB=(0,0,0)
				ModifyGraph /W=$(SpikeperSweep_graph) rgb($tempstring3a)=(48059,48059,48059)
				ModifyGraph  /W=$(SpikeperSweep_graph) nticks(bottom)=10,minor(bottom)=1,sep(bottom)=1
				SetAxis  /W=$(SpikeperSweep_graph) /A/N=0/E=0 bottom //DimOffset($stimwavetrim,0), (DimSize($stimwavetrim,0)*DimDelta($stimwavetrim,0))
				SetAxis  /W=$(SpikeperSweep_graph) /A/N=1/E=1 left
				Label  /W=$(SpikeperSweep_graph) Left "Sweep (#)"
				Label  /W=$(SpikeperSweep_graph) bottom "Time (s)"

				If (protocol==3)
					n+=1 //increment n for the pairs
				Endif

			Endfor
						
			//Append Stim Graph
			If (Exists(stimwave)==1)
				AppendtoGraph /W=$(SpikeperSweep_graph) /R=right $stimwavetrim
				ModifyGraph /W=$(SpikeperSweep_graph) rgb($stimwavetrim)=(34952,34952,34952)
				ModifyGraph /W=$(SpikeperSweep_graph) tick(right)=3,noLabel(right)=2
			Endif

			Graph_Panel(topGraph) //(SpikeperSweep_graph) //Display Graph Panel
			Button pVector3, disable=0
			Button pAvgSpikes, disable = 0
			
			
			//Plot Histograms
			If (Exists(stimwave)==1)
				If ((tempnum1==2&&tempnum4==0)||(tempnum1==2&&tempnum2==2))
					DoWindow /K $SpikeperSweep_histgraph
					Display /N=$(SpikeperSweep_histgraph) /K=1 /R=right $stimwavetrim
					ModifyGraph /W=$(SpikeperSweep_histgraph) rgb($stimwavetrim)=(34952,34952,34952)
					ModifyGraph /W=$(SpikeperSweep_histgraph) tick(right)=3,noLabel(right)=2
					Graph_Panel(SpikeperSweep_histgraph) //Display Graph Panel
					DoUpdate
					For (n=0; n<cursornum-1; n+=1)
						tempstring4 = "root:A:Avg:spikehistogram"+cursorNames[n]+cursorNames[n+1]
						string tempstring4name = "spikehistogram"+cursorNames[n]+cursorNames[n+1]
						AppendtoGraph /W=$(SpikeperSweep_histgraph) $(tempstring4)
						ModifyGraph /W=$(SpikeperSweep_histgraph) mode($tempstring4name)=5, rgb($tempstring4name)=(32768,32770,65535),hbFill($tempstring4name)=2,  useBarStrokeRGB($tempstring4name)=1
					Endfor
				Endif
			Endif //Deal with lack of stimwave at some point....
			
			
			Notebook $nb0 text=num2str(spiketotal1a)+" Total Events"
			If (checknum108==1)
				Notebook $nb0 text="\r"+num2str(spiketotal1b)+" Total 1st Events"
			Endif
			
			//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
			//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
			//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
			//////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
		Else // if cursors not checked
			Notebook $nb0 text="\r\r"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"\r"
			String sampleWaveTemp = FileNameTruncated+"_"+input_type
			Leftnum = DimOffset($sampleWaveTemp,0)*DimDelta($sampleWaveTemp,0)
			//Print leftnum
			Rightnum =  DimSize($sampleWaveTemp,0)*DimDelta($sampleWaveTemp,0)
			//Print rightnum
			
			Variable tempperiod = (1000*(1/tempfreq))/1000
			sprintf valAsStr, "%.3g", tempperiod
			tempperiod= str2num(valAsStr)
			
		
			AMPtemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMPt"
			STtemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_STt"
			Ltemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_Lt"
			EVENTtemp = FileNameTruncated+"to"+num2str(tempwavenum2)+"_Et"

			
			AMP = FileNameTruncated+"to"+num2str(tempwavenum2)+"_AMP"
			ST = FileNameTruncated+"to"+num2str(tempwavenum2)+"_ST"
			STsweep = ST+"swp"
			STsweepSingle = ST+"swp1"

			L = FileNameTruncated+"to"+num2str(tempwavenum2)+"_L"
			EVENT = FileNameTruncated+"to"+num2str(tempwavenum2)+"_E"

			String SThist = "root:A:Avg:spikehistogram"
			
			Killwaves /Z $(L)
			Killwaves /Z $(AMP)
			Killwaves /Z $(ST)
			Killwaves /Z $(STsweep)
			Killwaves /Z $(STsweepSingle)
			Killwaves /Z $(EVENT)
			Make /N=0 $STsweep=0
			Make /N=0 $STsweepSingle=0

			WAVE /Z temp2DWave = $(FileNameTruncated+input_type)
			If (WaveExists(temp2DWave)==0)
				Setdatafolder savedDF
				Abort "Input 2D wave not found: "+FileNameTruncated+input_type
			Endif
			waveDelta = DimDelta(temp2DWave, 0 )
				
			For (i=tempwavenum1-1; i< tempwavenum2; i+=1)
				
				//parse out one wave at a time from the 2D wave in order to use FindLevels
				MatrixOP/FREE wTemp = col(temp2DWave, i)
				SetScale /P x 0,waveDelta,"s", wTemp

				//calculate avg Latency
				If (checknum104==1)
					FindLevels /Q /B=(boxNum) /DEST=$(Ltemp) /EDGE=2 /M=(spikewidth)/R=(Leftnum,Rightnum) wTemp eventamp
					concatenate /NP /KILL {$(Ltemp)}, $L
				Endif	

				//Detect just a single event per stimulus period
				If(checknum108==1)	
					newWaveNumPoints = 0
					For (z=Leftnum;z<=Rightnum;z+=tempperiod)
						FindLevel /Q /B=(boxNum) /EDGE=2 /R=(z,z+tempperiod) wTemp eventamp
						If (V_flag==0)
							Make /O /N=1 $EVENTtemp = V_LevelX
							concatenate /NP /KILL {$(EVENTtemp)}, $EVENT
							newWaveNumPoints += 1
						Endif
					Endfor
					
					//Count the number of events per sweep (for single event per stim period
					WAVE wSTcountSingle=$(STsweepSingle)
					WaveNumPoints = numpnts($STsweepSingle)
					InsertPoints /M=0 WaveNumPoints, newWaveNumPoints, wSTcountSingle
					For (m=0; m<newWaveNumPoints; m+= 1)
						wSTcountSingle[WaveNumPoints+m] = i
					Endfor

					
				Endif							
					
				FindLevels /Q /B=(boxNum) /DEST=$(STtemp) /EDGE=2 /M=(spikewidth)/R=(Leftnum,Rightnum) wTemp eventamp

				WAVE STtempWave1 = $(STtemp)
				newWaveNumPoints=numpnts(STtempWave1)
				Make /O /N=(newWaveNumPoints) $AMPtemp
				WAVE AMPtempWave1 = $(AMPtemp)
					
				For (k=0;k<newWaveNumPoints;k+=1)
					templeftX = STtempWave1[k]
					temprightX = STtempWave1[k]+(3*spikewidth)
					//FindPeak /Q /B=1 /R=(templeftX,temprightX) wTemp
					tempMAXval = wavemax (wTemp, templeftX,temprightX) //V_PeakVal
					//FindPeak /Q /B=1 /N /R=(templeftX,temprightX) wTemp
					tempMINval = wavemin (wTemp, templeftX,temprightX) //V_PeakVal
					AMPtempWave1[k] = abs(tempMAXval)+abs(tempMINval)
				Endfor
				concatenate /NP /KILL {$(AMPtemp)}, $(AMP)		
				concatenate /NP /KILL {$(STtemp)}, $ST


				//Count the number of events per sweep
				WAVE wSTcount=$(STsweep)
				WaveNumPoints = numpnts($STsweep)
				InsertPoints /M=0 WaveNumPoints, newWaveNumPoints, wSTcount
				For (m=0; m<newWaveNumPoints; m+= 1)
					wSTcount[WaveNumPoints+m] = i
				Endfor

			Endfor

			If(tempnum1==2)
				Prompt HistBins, "Number of bins:"
				Prompt tempnum2, "Overwrite histogram?" popup "No;Yes"
				DoPrompt "Create spike time histogram", HistBins,tempnum2
			Endif		

			If ((V_flag==0)&&(((tempnum1==2)&&(tempnum4==0))||((tempnum1==2)&&(tempnum2==2))))
				//HISTOGRAM of the spikes for each cursor pair
				Make /O /N=(HistBins) $SThist=0
				Histogram /B=1 $ST,$SThist
			Elseif ((V_flag==0)&&(((tempnum1==2)&&(tempnum4==1))||((tempnum1==2)&&(tempnum2==1))))
				Histogram /A /B=2 $ST,$SThist
			Endif

			//Plot Histogram
			If ((V_flag==0)&&(((tempnum1==2)&&(tempnum4==0))||((tempnum1==2)&&(tempnum2==2))))
				DoWindow /K $SpikeperSweep_histgraph
				Display /N=$(SpikeperSweep_histgraph) /K=1 /R=right $stimwave
				ModifyGraph /W=$(SpikeperSweep_histgraph) rgb($stimwave)=(34952,34952,34952)
				ModifyGraph /W=$(SpikeperSweep_histgraph) tick(right)=3,noLabel(right)=2
				Graph_Panel(SpikeperSweep_histgraph) //Display Graph Panel
				string SThistname = "spikehistogram"
				AppendtoGraph /W=$(SpikeperSweep_histgraph) $(SThist)
				ModifyGraph /W=$(SpikeperSweep_histgraph) mode($SThistname)=5, rgb($SThistname)=(32768,32770,65535),hbFill($SThistname)=2,  useBarStrokeRGB($SThistname)=1
			Endif				
			
			//calculate avg time to first spike
			If (checknum104==1)

				WAVE wL = $L
				wavestats /Q wL
				pointnumber = V_npnts
				sprintf valAsStr, "%.3g", V_avg
				L_avg= str2num(valAsStr)
				
				sprintf valAsStr, "%.3g", V_sem
				L_sem= str2num(valAsStr)					
								
				sprintf valAsStr, "%.3g", (V_sdev/V_avg)
				L_cv= str2num(valAsStr)
					
				wavenumber = tempwavenum2-tempwavenum1+1
						
				Notebook $nb0 text="Latency--checked\r"			
				Notebook $nb0 text="FSL = "+num2str(L_avg)+" ± "+num2str(L_sem)+" SEM s; with a CV of "+num2str(L_cv)+" \r("+num2str(pointnumber)+" spikes in "+num2str(wavenumber)+" traces)\r"		
				TextBox /W=$topGraph /C/N=textbox2 /A=LT /X=0 /Y=5 /F=0 "\\Z10 FSL = "+num2str(L_avg)+" ± "+num2str(L_sem)+" SEM ms\r("+num2str(pointnumber)+" spikes in "+num2str(wavenumber)+" traces)"
			Else
				Notebook $nb0 text="Note: Latency/period--NOT checked\r"			
			Endif
				
			
			//calculate mean AMP
			WAVE wST = $ST
			pointnumber = numpnts(wST)
			AMP_avg = mean ($AMP,0,pointnumber)*1e12
			sprintf valAsStr, "%.3g", AMP_avg
			AMP_avg= str2num(valAsStr)
			
			//Subtract previous spike time from current spike time to get ISI
			String ISI = FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_ISI"
			Make /O /N=(pointnumber) $ISI
			Wave wISI=$ISI
			wISI = 0
			If (pointnumber>1)
				wISI[1,pointnumber-1] = wST[p] - wST[p-1]
			Endif
			//DeletePoints 0,1, wISI
			
			//this is not displayed because average ISI is meaningless for evoked spikes....
			variable ISI_avg = mean (wISI,1,pointnumber)*1000 //start at 1 since point 0 is zero ISI
			sprintf valAsStr, "%.3g", ISI_avg
			ISI_avg= str2num(valAsStr)

			Notebook $nb0 text=num2str(numpnts($ST ))+" events\r"		
			TextBox /W=$topGraph /C/N=textbox1 /A=LT /X=0 /Y=-3 /F=0 "\\Z10"+num2str(numpnts($ST ))+" events"+"\rAvg Amplitude = "+num2str(AMP_avg)+" pA"
	
			Graph_Panel(topGraph) //Display Graph Panel
			Button pAvgSpikes, disable = 0
			Button pVector2, disable=0
		Endif
		
		Notebook $nb0 text="\r\r"
	Endif
	Setdatafolder savedDF
	
	//Enable ISI button on tab and keep it enabled when switching tabs
	DoWindow /F JT_Controls
	MPTabProc ("6",1)
End

////////////////////////////////////////////////////////////////////////////////////////////////////
///Find Peaks for Graph Control Panel -- determine spike time and ISI for a concatenated single wave
// Function: Find_Peaks2
// Detect events in the active graph/concatenated wave and create spike-time, point-number, amplitude, and ISI waves for graph-panel analysis.
Function Find_Peaks2(ctrlName): ButtonControl
	string ctrlName
	string accumwave
	string tempfolder1
	string valAsStr
	
	variable baseval
	variable boxNum=1
	variable tempwavenum1
	variable tempwavenum2
	variable i,k,xcsrA,xcsrB
	variable checknum,leftval,rightval
	variable templeftX,temprightX,tempMAXval,tempMINval
	
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	Variable spikewidth = (2/3)*spiketime // /1000
		
	//Create truncated name from tempwave
	//Get wavename from wave in graph
	wave wInputwave = WaveRefIndexed("",0,1)
	string dfinputname = GetWavesDataFolder(wInputwave,1)
	String inputname = PossiblyQuoteName(NameofWave(wInputwave))
	String inputwave = dfinputname+inputname
	
	If (strlen(CsrInfo(A))>0&&strlen(CsrInfo(B))>0) 	//If cursors exist, then find Levels inbetween CURSORS A & B!!
		leftval = pcsr(A)
		rightval = pcsr(B)
	Else
		leftval = DimOffset(wInputwave, 0)
		rightval = numpnts(wInputwave)
	Endif		
	//Print leftval
	//Print rightval
	
	//Find events and save as spike times
	String STname = PossiblyQuoteName(NameofWave(wInputwave) +"_ST")
	String STpath = dfinputname+STname
	Make /O /N=1 $STpath //places wave in Concat folder
	WAVE wST = $STpath	
	FindLevels /Q /B=(boxNum) /D=wST /EDGE=2 /R=[leftval,rightval] /M=(spikewidth) wInputwave eventamp


	variable pointnumber = numpnts(wST)
	String AMPname = PossiblyQuoteName(NameofWave(wInputwave) +"_AMP")
	String AMPpath = dfinputname+AMPname
	Make /O /N=(pointnumber) $AMPpath
	WAVE wAMP = $AMPpath
					
	For (k=0;k<pointnumber;k+=1)
		templeftX = wST[k]
		temprightX = wST[k]+(3*spikewidth)
		tempMAXval = wavemax (wInputwave, templeftX,temprightX) //V_PeakVal
		tempMINval = wavemin (wInputwave, templeftX,temprightX) //V_PeakVal
		wAMP[k] =abs(tempMAXval)+abs(tempMINval)
	Endfor
		
	//Find events and save as point numbers
	String PTname = PossiblyQuoteName(NameofWave(wInputwave) +"_PT")
	String PTpath = dfinputname+PTname
	Make /O /N=1 $PTpath
	WAVE wPT = $PTpath	
	FindLevels /P /Q /B=(boxNum) /D=wPT /EDGE=2 /R=(leftval,rightval) /M=(spikewidth) wInputwave eventamp	
	
	
	//calculate mean AMP
	variable AMP_avg = mean (wAMP,0,pointnumber)*1e12
	sprintf valAsStr, "%.3g", AMP_avg
	AMP_avg= str2num(valAsStr)
	
	//Subtract previous spike time from current spike time to get ISI
	String ISIname = PossiblyQuoteName(NameofWave(wInputwave) +"_ISI")
	String ISIpath = dfinputname+ISIname
	Make /O /N=(pointnumber) $ISIpath
	Wave wISI=$ISIpath
	wISI = 0
	If (pointnumber>1)
		wISI[1,pointnumber-1] = wST[p] - wST[p-1]
	Endif

	//calculate avg ISI
	variable ISI_avg = mean (wISI,1,pointnumber)*1000
	sprintf valAsStr, "%.3g", ISI_avg
	ISI_avg= str2num(valAsStr)
	
	String topGraph = WinName(0, 1)	// Name of top graph
	
	If (cmpstr(ctrlName,"pfindpeakstemp")==1)
		AppendToTable /W=ISI_table wISI
		Dowindow /F ISI_table
		Dowindow /F $topGraph
	Endif

	TextBox  /C/N=textbox2 /X=80.00/Y=-0.20 /A=LT /F=0 "\\Z10"+num2str(numpnts(wST ))+" events "+"\rAvg ISI = "+num2str(ISI_avg)+" ms"+"\rMean spikes = "+num2str(AMP_avg)+" pA"

	Button ptonestart, disable = 0
	Button phistogram, disable = 0
	Button pvector1, disable = 0
	Button pInstfreq, disable = 0
	
	controlInfo checkH3
	variable checknumH3 = V_Value
	If (checknumH3==1)	
		Display_Peaks2(inputwave)
	Endif
End


/////////////////////////////////////////////////////////////////////////////////////
//Display found peaks for Concatenated waves only: Graph Control Panel

// Function: Display_Peaks2
// Extract windows around detected spikes from a concatenated wave, display individual spike snippets, and overlay their average.
Function Display_Peaks2(ctrlName)
	string ctrlName
	variable i,n
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
			
	//Get wave name from concatwave in graph
	WAVE wInputwave = WaveRefIndexed("",0,3)
	string inputname= NameofWave(wInputwave)	
	string dfinputname = GetWavesDataFolder(wInputwave,1)
	
	String wAMPname = possiblyquotename(NameofWave(wInputwave)+"_AMP")
	String wAMPpath = dfinputname+wAMPname
	WAVE wAMP = $wAMPpath
	String wPTname = possiblyquotename(NameofWave(wInputwave)+"_PT")
	String wPTpath = dfinputname+wPTname
	WAVE wPT = $wPTpath
	
	Variable SpikeWindow = 2000
	String savedDataFolder = GetDataFolder(1)	// Save

	NewDataFolder/O/S $(ctrlName)

	//Make avg wave
	String outputname = possiblyquotename(inputname+"_spike_avg")
	Make /O /N=(SpikeWindow) $outputname
	Wave avgwave = $outputname
	avgwave=0
	SetScale /P y,0,DimDelta(wInputwave, 0), WaveUnits(wInputwave, 1), avgwave
	SetScale/P x, 0,DimDelta(wInputwave, 0), "s", avgwave 
	
	Variable pointnumber = DimSize(wPT,0)
	
	For (i=0; i<Dimsize(wPT,0); i+=1)

		Make /O /N=(SpikeWindow) $(num2str(i))
		WAVE wSpike = $(num2str(i))
		wSpike=0
		SetScale /P y,0,DimDelta(wInputwave, 0), WaveUnits(wInputwave, 1), wSpike
		SetScale/P x, 0,DimDelta(wInputwave, 0), "s", wSpike 
		
		If (i==0)
			DoWindow /K Spike_Graph
			Display /N=Spike_Graph /W=(300,100,800,410 ) /K=1 wSpike as (inputname+"_Spikes_"+num2str(1)+"to"+num2str(pointnumber))
		Else
			AppendtoGraph wSpike
		Endif
		
		For (n=0; n<SpikeWindow; n+=1)
			Variable srcPoint = (wPT[i]-(SpikeWindow/2))+n
			If ((srcPoint>=0)&&(srcPoint<numpnts(wInputwave)))
				wSpike[n] = wInputwave[srcPoint]
				avgwave[n] += wSpike[n]
			Else
				wSpike[n] = NaN
			Endif
		Endfor
		//wAMP[i] = wavemax (wSpike) - wavemin (wSpike)
	Endfor

	//calculate mean AMP
	variable AMP_mean = mean (wAMP,0,pointnumber)*1e12
	variable AMP_max = wavemax (wAMP)*1e12
	variable AMP_min = wavemin (wAMP)*1e12
	
	String valAsStrMean
	sprintf valAsStrMean, "%.3g", AMP_mean
	String valAsStrMax
	sprintf valAsStrMax, "%.3g", AMP_max
	String valAsStrMin
	sprintf valAsStrMin, "%.3g", AMP_min
	
	Print "Smallest spike ampitude is "+valAsStrMin+" pA"
	Print "Largest spike ampitude is "+valAsStrMax+" pA"
	Print "Mean spike ampitude is "+valAsStrMean+" pA"
	
	//Average the wave
	If (numpnts(wPT)>0)
		avgwave = avgwave/(numpnts(wPT))
	Endif
	
	//Graph the average wave
	ModifyGraph rgb=(0,0,0)
	SetAxis/A/N=2/E=0 left
	
	AppendToGraph /W=Spike_Graph /L=XgridLeft/B=XgridBot avgwave
	//ModifyGraph rgb( $(inputname+"_spike_avg"))=(26411,1,52428)
	ModifyGraph freePos(XgridLeft)={0,XgridBot}
	ModifyGraph freePos(XgridBot)={-1,XgridLeft}
	ModifyGraph axisEnab(XgridLeft)={0.8,0.9}
	ModifyGraph axisEnab(XgridBot)={0.8,0.95}
	ModifyGraph tick=3,noLabel=2,axThick=0, margin=-1


	SetDataFolder savedDataFolder			// and restore
	return 1
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Analyze the ISI attributes

// Function: analyze_ISI
// Run secondary ISI/spike-time analyses such as binning, recurrence plots, spike counts per sweep, latency differences, amplitude ratios, and vector-strength summaries.
Function analyze_ISI (ctrlName):ButtonControl
	string ctrlName
	string cmd
	string Concatwave
	string SpikeTimewave
	string SpikeTimeWavebin
	string ISIwave
	string ISIwavebin
	string Spikepersec
	string Spikepersechist
	string inputwave
	string inputname
	variable analysisType,analysisNum 
	SVAR tempwave = root:A:tempwave

	variable i
	variable n
	variable j
	variable bin=1
	variable checknum

	String savedDataFolder = GetDataFolder(1)	// Save

	//Determine if  a concatWave will be analyzed
	controlInfo /W=zPhys_Settings check110
	checknum = V_Value

	If (checknum==0)
	
		Prompt analysisType, "Type of Analysis:", popup "Find #spikes per sweep;Latency from 1st to 2nd spike;Amplitude of 2nd to 1st spike;Colorize sequential spike times;Vector strength stats;CV of wave values;Recurrence Plot"

	ElseIf (checknum==1)//check for ISI wave in Concat folder
	
		Prompt analysisType, "Type of Analysis:", popup "Bin ISIs; Recurrence Plot"
	
	Endif
	
	DoPrompt "Select Analysis", analysisType
			
	If (V_flag==0&&checknum==0&&analysisType==1)		
		findSpikesinSweeps(tempWave)
		Return 0
		
	ElseIf (V_flag==0&&checknum==0&&analysisType==2)		
		findLatDiff(tempWave)
		Return 0
			
	ElseIf (V_flag==0&&checknum==0&&analysisType==3)		
		find_ALR_amplitude(tempWave)
		Return 0

	ElseIf (V_flag==0&&checknum==0&&analysisType==4)		
		colorizeSpiketimes(tempWave)
		Return 0
					
	ElseIf (V_flag==0&&checknum==0&&analysisType==5)		
		stimfreqstats(tempWave)
		Return 0
		
	ElseIf (V_flag==0&&checknum==0&&analysisType==6)		
		CVwavestats(tempWave)
		Return 0

	ElseIf (V_flag==0&&checknum==0&&analysisType==7)		
		recurrencePlot(tempwave,1,-1)
		Return 0
				
	ElseIf (V_flag==0&&checknum==1)
		SetDataFolder root:A:Concat:
		String concatISIwaves = WaveList("*_ISI", ";", "")
		String concatISIwave = Stringfromlist(0,concatISIwaves)
		Wave /Z wavecheck2 = $concatISIwave 
	
		If(waveexists(wavecheck2)==1)
			Prompt inputwave, "Input Wave", popup WaveList("*_ISI", ";", "")
		Else
			SetDataFolder savedDataFolder
			Abort "no ISI waves"
		Endif
	Elseif (V_flag!=0)
		Abort
	Endif					
				

	If (checknum==1&&analysisType==2)			
		Prompt bin, "Recurrence offset:"
		Prompt analysisNum, "Analyze wave or waves?", popup "Current wave; All waves in folder"
		DoPrompt "Select Analysis",inputwave,bin,analysisNum	
		If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
			recurrencePlot(inputwave,analysisNum,bin)
		Endif
		SetDataFolder savedDataFolder
		Return 0
		
	Elseif (checknum==1&&analysisType==1)			
		Prompt bin, "Size of Bins:"
		DoPrompt "Select Analysis",inputwave,bin		
	Endif

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		//Create truncated name from tempwave
		inputwave = ParseFilePath (3,inputwave,":",0,0)
		
		
		string parsestring,pa,pd,pf,pg
		variable pb,pc,pe,ph
		String tempending, pbtemp
		
		parsestring = "%[A-Z]%d%*[_]%d%*[_]%s"
		sscanf inputwave, parsestring, pa,pb,pc,tempending
		
		
		
		///Extract the base name of the ISI wave
		If (cmpstr(tempending[0],"C")==0)
			parsestring = "%[A-Z]%d%*[_]%d%*[_]%[C]%d%[t]%[o]%d%*[_]%*[I]%*[S]%*[I]"
			sscanf inputwave, parsestring, pa,pb,pc,pd,pe,pf,pg,ph
			//correct for single digit months
			If (strlen(num2str(pb))==5)
				pbtemp = "0"+num2str(pb) 
				//print pa,pb,pc,pd,pe,pf,pg,ph
				inputname = pa+pbtemp+"_"+num2str(pc)+"_"+pd+num2str(pe)+pf+pg+num2str(ph)
				print inputname	
			Else
				//print pa,pb,pc,pd,pe,pf,pg,ph
				inputname = pa+num2str(pb)+"_"+num2str(pc)+"_"+pd+num2str(pe)+pf+pg+num2str(ph)	
			Endif
		
			//if it's not a Concat ISIwave, then extract the basename without the "C" and pd
		Else
			parsestring = "%[A-Z]%d%*[_]%d%*[_]%d%[t]%[o]%d%*[_]%*[I]%*[S]%*[I]"
			sscanf inputwave, parsestring, pa,pb,pc,pe,pf,pg,ph
			//correct for single digit months
			If (strlen(num2str(pb))==5)
				pbtemp = "0"+num2str(pb) 
				//print pa,pb,pc,pd,pe,pf,pg,ph
				inputname = pa+pbtemp+"_"+num2str(pc)+"_"+num2str(pe)+pf+pg+num2str(ph)
				//print inputname	
			Else
				//print pa,pb,pc,pd,pe,pf,pg,ph
				inputname = pa+num2str(pb)+"_"+num2str(pc)+"_"+num2str(pe)+pf+pg+num2str(ph)	
			Endif
		Endif
			
		
		Concatwave = inputname
		SpikeTimewave = inputname+"_ST"
		SpikeTimeWavebin = inputname+"_STb"

		ISIwave = inputname+"_ISI"
		ISIwavebin = inputname+"_ISIb"

		Spikepersec = inputname+"_SS"
		Spikepersechist = inputname+"_SSh"
	
				
		Make /O /N=(numpnts($ISIwave)/bin) $ISIwavebin=0
		SetScale /P x,0,bin,"", $ISIwavebin
		Make /O /N=(numpnts($SpikeTimeWave)/bin) $SpikeTimeWavebin=0
	
		Wave wSpiketime=$SpikeTimewave
		Wave wISI=$ISIwave
		Wave wISIbin = $ISIwavebin
		Wave wSpiketimebin = $SpikeTimeWavebin
	
		//Bin the spiketimes and bin and average the ISItimes
		j=0
		For (i=0; i<=(numpnts($ISIwave)-bin); i+= bin)
			For (n=0; n<bin; n+=1)
				wISIbin[j] += wISI[i+n]
			Endfor
			wISIbin[j]=wISIbin[j]/bin
			wSpiketimebin[j] += wSpiketime[i+(bin-1)]
			j+=1
		Endfor
	
	
		//Convert Spikes to raster
		Duplicate /O $SpikeTimeWave $Spikepersec
		Wave wSpikepersec = $Spikepersec
		wSpikepersec = wSpikepersec - floor(wSpikepersec)


		If (WaveExists($Concatwave)==1)
			Wave wConcat=$Concatwave
			//If multiple traces are concatenated, then Display the average Spiketime per Trace
			Variable wavelength = DimSize(wConcat,0)*DimDelta(wConcat,0)
			//Bin the values per Trace
			variable bins = (wavelength)/bin
			Make /O /N=(bins) $Spikepersechist
			Histogram /B={0,bin,bins} /C /R=(0) $SpikeTimeWave, $Spikepersechist


			//also display the Concatenated wave
			DoWindow /K Concat_graph
			Display /N=Concat_graph /W=(350,50,850,250 ) /K=1 $Concatwave
			ModifyGraph rgb = (0,0,0)
			SetAxis/A/N=1/E=1 bottom
			SetAxis/A/N=2/E=2 left
			Label left "Current (pA)";DelayUpdate
			Label bottom "Time (s)"
		Endif

		//Graph Event comparisons
		DoWindow /K Spike_graph
		Display /N=Spike_graph /W=(350,300,850,500 ) /K=1 $SpikeTimeWave
		ModifyGraph rgb = (0,0,0)
		Label left "Time (s)";DelayUpdate
		Label bottom "Event #"
		ModifyGraph swapXY=1	//SWAP THE AXES
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=1/E=1 left

		DoWindow /K ISI_graph
		Display /N=ISI_graph /W=(350,550,850,750 ) /K=1 $ISIwave
		ModifyGraph mode=5,hbFill=4,useNegPat=1,useBarStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "ISI (s)";DelayUpdate
		Label bottom "Event #"

		DoWindow /K ISIbin_graph
		Display /N=ISIbin_graph /W=(350,800,850,1000 ) /K=1 $ISIwavebin
		ModifyGraph mode=0,rgb=(0,0,0)
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "Average ISI  of "+num2str(bin)+" events/bin";DelayUpdate
		Label bottom "Event #"
	
		///Graph Time (s) comparisons
	
		DoWindow /K Spikepersec_graph
		Display /N=Spikepersec_graph /W=(900,50,1400,250 ) /K=1 $Spikepersec vs $SpikeTimeWave
		ModifyGraph mode=2,rgb=(0,0,0), tick(left)=3,noLabel(left)=2
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left -0.5,1.5
		Label bottom "Time (s)"
	
		If (WaveExists($Concatwave)==1)
			DoWindow /K SpikeHist_graph
			Display /N=SpikeHist_graph /W=(900,300,1400,500 ) /K=1 $Spikepersechist
			ModifyGraph mode=4,marker=16,rgb=(21845,21845,21845),useMrkStrokeRGB=1
			SetAxis/A/N=1/E=1 bottom
			SetAxis/A/N=2/E=1 left
			Label left "# of events in "+num2str(bin)+" second bins"
			Label bottom "Bin #"
		Endif
		
		DoWindow /K ISItime_graph
		Display /N=ISItime_graph /W=(900,550,1400,750 ) /K=1 $ISIwave vs $SpikeTimeWave
		ModifyGraph mode=3,marker=19,rgb=(26214,26214,26214),useMrkStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "ISI (s)";DelayUpdate
		Label bottom "Time (s)"	

	
		DoWindow /K ISIbinvsSpikeTimebin_graph
		Display /N=ISIbinvsSpikeTimebin_graph /W=(900,800,1400,1000 ) /K=1 $ISIwavebin vs $SpikeTimeWavebin
		ModifyGraph mode=4,marker=19,rgb=(26214,0,0),useMrkStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "Average ISI of  "+num2str(bin)+"  events"
		Label bottom "Time (s)"

		//If Layout checkbox is checked
		controlInfo /W=zPhys_Settings check103
		Variable checknum2 = V_Value
		If (checknum2==1)
			DoWindow /K TimeLayout	
			NewLayout /N=TimeLayout /K=1 as inputname
			AppendLayoutObject /W=TimeLayout graph Spikepersec_graph	
			AppendLayoutObject /W=TimeLayout graph SpikeHist_graph
			AppendLayoutObject /W=TimeLayout graph ISItime_graph
			AppendLayoutObject /W=TimeLayout graph ISIbinvsSpikeTimebin_graph
			Sprintf cmd, "Tile/A=(0,1)"
			Execute cmd
	
			DoWindow /K EventLayout	
			NewLayout /N=EventLayout /K=1 as inputname
			AppendLayoutObject /W=EventLayout graph Concat_graph
			AppendLayoutObject /W=EventLayout graph Spike_graph
			AppendLayoutObject /W=EventLayout graph ISI_graph
			AppendLayoutObject /W=EventLayout graph ISIbin_graph
			Sprintf cmd, "Tile/A=(0,1)"
			Execute cmd
		
		Endif
	Endif //For DoPrompt
	SetDataFolder savedDataFolder
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Vector Strength of Waves: "JT_Controls" Panel

// Function: vector1
// Calculate vector strength from spike-time/latency waves selected from the panel workflow.
Function vector1(ctrlName): ButtonControl
	string ctrlName
	string cmd
	string vectorwave
	string vectorwavex
	string vectorwavey
	string vectorwavehist
	String inputname
	string valAsStr
	

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	NVAR tempfreq = root:A:tempfreq
	
	variable f =tempfreq
	variable vectorstrength
	variable vectorstrengthround
	variable tempvar
	String currentDF = GetDataFolder(1)	// Save

	variable folderselect,spikeselect
	Prompt folderselect, "Select:", popup "Current folder;Concatenated-waves folder; All data folders"
	Prompt spikeselect, "Select:", popup "First spike;All spikes"
	DoPrompt "Vector Strength from folder(s)", folderselect,spikeselect

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		If (folderselect<3)
		
			If (folderselect==2)
				SetDataFolder root:A:Concat:
				Prompt inputname, "Select spike time wave:", popup WaveList("*_ST*", ";", "")
			Elseif (spikeselect==1)
				Prompt inputname, "Select 1st spike latencies wave:", popup WaveList("*_L1*", ";", "")
			Elseif (spikeselect==2)
				Prompt inputname, "Select spike latencies wave:", popup WaveList("*_L*", ";", "")
			Endif
			Prompt f, "frequency"
			DoPrompt "Select SpikeTime wave and analysis frequency", inputname,f	
	
			If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

				Wave /Z wavecheck = $inputname 
				If(waveexists(wavecheck)!=1)
					SetDataFolder currentDF
					Abort "No waves exist"
				Endif

				String dfinputname = GetWavesDataFolder($inputname,1)
				String inputwave = dfinputname+possiblyquotename(inputname)
				String vectorpath = "root:A:V:"
				vectorwave = vectorpath + possiblyquotename (inputname+"_V")
				vectorwavex = vectorpath + possiblyquotename (inputname+"_X")
				vectorwavey = vectorpath + possiblyquotename (inputname+"_Y")
				vectorwavehist = vectorpath + possiblyquotename (inputname+"_VH")
	
				tempfreq = f
		
				Duplicate /O $inputwave $vectorwave
				Duplicate /O $inputwave $vectorwavex
				Duplicate /O $inputwave $vectorwavey
				Wave v = $vectorwave
				Wave vx = $vectorwavex
				Wave vy = $vectorwavey

				//Transform latency to values within a single cycle with Y=(Y/(1000/60))-floor(Y/(1000/60)); 1000 is for ISI in ms
				v = (v/(1/f))-floor(v/(1/f))
		
				//1st: transform the latency floors to radians ((2*pi*v //360*v times pi/180)) then: unit vector angles with x (use cosine) and y (use sine) coordinates
				vx = cos(2*pi*v)
				vy = sin(2*pi*v)


		
		
				//sum of vector x and y : SQRT(POWER(B2,2)+POWER(C2,2))/D2
				vectorstrength = (sqrt(       (sum(vx))^2      +        (sum(vy))^2        ))/numpnts(v)
				sprintf valAsStr, "%.3g", vectorstrength
				vectorstrength= str2num(valAsStr)
	
				print "Vector Strength at "+num2str(f)+"Hz is "+num2str(vectorstrength)
		
				KillWaves vx, vy 

		
				//Bin the values per cycle
				variable bins = 60
				tempVar = 360/bins //set the wave scaling to degrees for making polar plots //WaveMax(vh)
				Variable binWidth = 1/bins
				Make /O /N=(bins) $vectorwavehist
				Histogram /B={0,binWidth,bins} /C /R=(0) $vectorwave, $vectorwavehist
				SetScale/P x 0,tempVar,"", $vectorwavehist


				//DoWindow /K VectorHist_graph
				Display /N=VectorHist_graph /W=(900,300,1400,500 ) /K=1 $vectorwavehist   as (inputname+"_VH")
				ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(21845,21845,21845)
				SetAxis/A/N=0/E=1 bottom
				SetAxis/A/N=1/E=1 left
				Label left "# of Events"
				Label bottom num2str(f)+" Hz unit cycle"+" (degrees)"
				//CurveFit/M=2/TBOX = 256/W=0 gauss, $vectorwavehist /D
				TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Vector strength = "+num2str(vectorstrength)+", "+num2str(numpnts($inputwave))+" events"

				SetDataFolder currentDF

			Endif
		
		ElseIf (folderselect==3)
			//This function is all the way down in this procedure file***
			VectorfromGraphs(ctrlName,spikeselect)	
		Endif
	Endif
	
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Vector Strength of Waves: Graph Control Panel

// Function: vector2
// Calculate vector strength from waves associated with the active graph-panel workflow.
Function vector2(ctrlName): ButtonControl
	string ctrlName
	string cmd
	string vectorwave
	string vectorwavex
	string vectorwavey
	string vectorwavehist
	string valAsStr
	

	String currentDF = GetDataFolder(1)	// Save
	NVAR tempfreq = root:A:tempfreq
	variable f =tempfreq
	variable vectorstrength
	variable vectorstrengthround
	variable tempvar

	//Determine if  "1 event per period" was checked
	controlInfo /W=zPhys_Settings check108
	variable checknum108 = V_Value
		
	//Get ST wave:
	wave wave1 = WaveRefIndexed("",0,1)
	string dfinputname = GetWavesDataFolder(wave1,1)
	SetDataFolder dfinputname
	Variable inputtype
	String inputname, inputwave

	If (cmpstr(ctrlName,"pvector2")==0) //Button for detecting spikes with NO cursors
		If(checknum108==1)
			Prompt inputtype, "Select", popup  "All events; First event only"
			DoPrompt "Select event type to analyze", inputtype
			If (V_flag==0&&inputtype==1)	
				Prompt inputname, "Select latency wave:", popup WaveList("*_L*", ";", "")
			ElseIf (V_flag==0&&inputtype==2)	
				Prompt inputname, "Select 1st event wave:", popup WaveList("*_L1*", ";", "")
			Else
				Abort "Cancelled"
			Endif	
		Else
			Prompt inputname, "Select latency wave:", popup WaveList("*_L*", ";", "")
		Endif

	ElseIf (cmpstr(ctrlName,"pvector3")==0)  //Button for detecting spikes with cursors
		Prompt inputname, "Select latency wave:", popup WaveList("*_L*", ";", "")
	
	ElseIf (cmpstr(ctrlName,"pvector1")==0)  //Button for detecting spikes from concat folder
		Prompt inputname, "Select spike time wave:", popup WaveList("*_ST", ";", "")
		
	Else
		Prompt inputname, "Select a wave with spike times:", popup WaveList("*", ";", "")
	Endif
	
	Prompt f, "frequency"
	DoPrompt "Analyze for what frequency?", inputname,f


	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		
		tempfreq = f //update tempfreq
		
		inputwave = dfinputname+possiblyquotename(inputname)
		String vectorpath = "root:A:V:"
		vectorwave = vectorpath + possiblyquotename (inputname+"_V")
		vectorwavex = vectorpath + possiblyquotename (inputname+"_X")
		vectorwavey = vectorpath + possiblyquotename (inputname+"_Y")
		vectorwavehist = vectorpath + possiblyquotename (inputname+"_VH")
		
		Duplicate /O $inputwave $vectorwave
		Duplicate /O $inputwave $vectorwavex
		Duplicate /O $inputwave $vectorwavey
		Wave v = $vectorwave
		Wave vx = $vectorwavex
		Wave vy = $vectorwavey
		//Transform latency to values within a single cycle with Y=(Y/(1000/60))-floor(Y/(1000/60)); 1000 is for ISI in ms
		v = (v/(1/f))-floor(v/(1/f))
		
		//1st: transform the latency floors to radians then: unit vector angles with x (use cosine) and y (use sine) coordinates
		vx = cos(2*pi*v)
		vy = sin(2*pi*v)
		
		
		//sum of vector x and y : SQRT(POWER(B2,2)+POWER(C2,2))/D2
		vectorstrength = sqrt((sum(vx))^2+(sum(vy))^2)/numpnts(v)
		sprintf valAsStr, "%.3g", vectorstrength
		vectorstrength= str2num(valAsStr)
		print "Vector Strength at "+num2str(f)+"Hz is "+num2str(vectorstrength)
		
		KillWaves vx, vy 

		
		//Bin the values per cycle
		variable bins = 60
		tempVar = 360/bins //set the wave scaling to degrees for making polar plots //WaveMax(vh)
		Variable binWidth = 1/bins
		//Make /O /N=(bins) $vectorwavehist ///DEST in Igor7
		Histogram /B={0,binWidth,bins} /C /R=(0) /DEST=$vectorwavehist $vectorwave
		SetScale/P x 0,tempVar,"", $vectorwavehist

		//DoWindow /K VectorHist_graph
		Display /N=VectorHist_graph /W=(900,300,1400,500 ) /K=1 $vectorwavehist   as (inputname+"_VH")
		ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(21845,21845,21845)
		SetAxis/A/N=0/E=1 bottom
		SetAxis/A/N=1/E=1 left
		Label left "# of Events"
		Label bottom num2str(f)+" Hz unit cycle"+" (degrees)"
		//CurveFit/M=2/TBOX = 256/W=0 gauss, $vectorwavehist /D
		TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Vector strength = "+num2str(vectorstrength)+", "+num2str(numpnts($inputwave))+" events"

	Endif
	SetDataFolder currentDF
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Vector Strength of Waves: "JT_Controls" Panel

// Function: vector3
// Calculate vector strength from spike-time waves generated from multi-sweep graphs.
Function vector3(ctrlName): ButtonControl
	string ctrlName
	string cmd
	string inputwavetrunc
	string vectorwave
	string vectorwavex
	string vectorwavey
	string vectorwavehist
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
			
	NVAR tempfreq = root:A:tempfreq
	
	variable f =tempfreq
	variable vectorstrength
	variable vectorstrengthround
	variable tempvar
	
	String currentDF = GetDataFolder(1)	// Save

	
	Prompt f, "frequency"
	DoPrompt "Select frequency for analysis", f

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		
		tempfreq = f
		
		String topGraph = WinName(0, 1)	// Name of top graph
	
		//determine whether it's a single concatenated wave or multiple sweeps
		String Traces=TraceNameList(topGraph,";",1)
		If  (ItemsinList(Traces)>1)
			//get full path and name of wave
			wave wave1 = WaveRefIndexed("",0,3)
			string inputname1= NameofWave(wave1)	
			string wave1folder = GetWavesDataFolder (wave1,1)
			SetDataFolder wave1folder
			NVAR sweepStartnum
			NVAR d		
			SVAR FileNameTruncated
	
			
			String stimwave = FileNameTruncated+"_"+num2str(sweepStartnum)+stim_type
			If (Exists(stimwave)==1)
				wave wave2 = WaveRefIndexed("",(ItemsInList(Traces)-2),3) //last wave
			Else
				wave wave2 = WaveRefIndexed("",(ItemsInList(Traces)-1),3) //last wave
			Endif

			string inputname2= NameofWave(wave2)	

			//Determine first and last wave
			Variable tempwavenum1
			variable tempwavenum2
			String tempscanstring =FileNameTruncated+"_%f"+input_type
			sscanf inputname1, tempscanstring, tempwavenum1
			sscanf inputname2, tempscanstring, tempwavenum2

			String STwave=FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_ST"
			
			WAVE wST = $(STwave)

			vectorwave = "root:A:V:"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_V"
			vectorwavex = "root:A:V:"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_X"
			vectorwavey = "root:A:V:"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_Y"
			vectorwavehist = "root:A:V:"+FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_VH"

			Duplicate /O wST $vectorwave
			Duplicate /O wST $vectorwavex
			Duplicate /O wST $vectorwavey
			Wave v = $vectorwave
			Wave vx = $vectorwavex
			Wave vy = $vectorwavey
			//Transform latency to values within a single cycle with Y=(Y/(1000/60))-floor(Y/(1000/60)); 1000 is for ISI in ms
			v = (v/(1/f))-floor(v/(1/f))
		
			//1st: transform the latency floors to radians then: unit vector angles with x (use cosine) and y (use sine) coordinates
			vx = cos(2*pi*v) //this calculates the x-length of a unit vector of angle "v" in radians
			vy = sin(2*pi*v)
		
		
			//sum of vector x and y : SQRT(POWER(B2,2)+POWER(C2,2))/D2
			vectorstrength = sqrt((sum(vx))^2+(sum(vy))^2)/numpnts(v)
			//vectorstrengthround = (round(100*vectorstrength))/100
			print "Vector Strength at "+num2str(f)+"Hz is "+num2str(vectorstrength)
		
			KillWaves vx, vy 

		
			//Bin the values per cycle
			variable bins = 60
			tempVar = 360/bins //set the wave scaling to degrees for making polar plots //WaveMax(vh)
			Variable binWidth = 1/bins
			Make /O /N=(bins) $vectorwavehist
			Histogram /B={0,binWidth,bins} /C /R=(0) $vectorwave, $vectorwavehist
			SetScale/P x 0,tempVar,"", $vectorwavehist

			//DoWindow /K VectorHist_graph
			Display /N=VectorHist_graph /W=(900,300,1400,500 ) /K=1 $vectorwavehist
			ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(21845,21845,21845)
			SetAxis/A/N=0/E=1 bottom
			SetAxis/A/N=1/E=1 left
			Label left "# of Events"
			Label bottom num2str(f)+" Hz unit cycle"+" (degrees)"
			//CurveFit/M=2/TBOX = 256/W=0 gauss, $vectorwavehist /D
			TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Vector strength = "+num2str(vectorstrength)+", "+num2str(numpnts(wST))+" events"
			SetDataFolder currentDF
		Else
			Abort "Only one wave on graph"
		Endif
	Endif
End

/////////////////////////////////////////////////////////////////////////////////////
// Average spike number per bin
// Function: Spikes_avg2
// Average spike times by sweep/bin for multi-sweep spike-time waves.
Function Spikes_avg2 (ctrlName)
	String ctrlName
	Variable i,n,m
	
	String STwave
	String currentDF = GetDataFolder(1)
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
			
	If (cmpStr(ctrlName,"pAvgSpikes")==0)
		Variable bin=10
		Prompt bin, "What size bins?"
		DoPrompt "Determine average spike time", bin
	
		If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
			Abort "Cancelled!"
		Endif
		String topGraph = WinName(0, 1)	// Name of top graph
		string inputname1, inputname2
		string wavefolder 
		//determine whether it's a single concatenated wave or multiple sweeps
		String Traces=TraceNameList(topGraph,";",1)
		If  (ItemsinList(Traces)>1)
			//get full path and name of wave
			wave wave1 = WaveRefIndexed("",0,3) //first wave
			wavefolder = GetWavesDataFolder (wave1,1)
			SetDataFolder wavefolder

			NVAR sweepStartnum
			NVAR d
			SVAR FileNameTruncated
			
			String stimwave = FileNameTruncated+"_"+num2str(sweepStartnum)+stim_type
			If (Exists(stimwave)==1)
				wave wave2 = WaveRefIndexed("",(ItemsInList(Traces)-2),3) //last wave
			Else
				wave wave2 = WaveRefIndexed("",(ItemsInList(Traces)-1),3) //last wave
			Endif			
			
			inputname1= NameofWave(wave1)	
			inputname2= NameofWave(wave2)	

			//Determine first and last wave
			Variable tempwavenum1
			variable tempwavenum2
			String tempscanstring =FileNameTruncated+"_%f"+input_type
			sscanf inputname1, tempscanstring, tempwavenum1
			sscanf inputname2, tempscanstring, tempwavenum2
			
			If (tempwavenum2<=tempwavenum1)
				Abort "wave error!"
			Endif

			STwave = FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_ST"
		Else
			Abort "Only one wave on graph"
		Endif
	Else
		Stwave = ctrlName
	Endif
		
	String STsweep = STwave+"_swp"
	String STwavebin = STwave+"_bin"
	Variable NumSweeps
		
	If (cmpStr(ctrlName,"pAvgSpikes")==0)
		NumSweeps = bin
	Else
		NumSweeps = WaveMax($STsweep)
	Endif	
		
	Variable NumPoints = DimSize($STwave,0)
	Variable NumPntsSweep
	Make /O /N=(NumSweeps) $STwavebin=0

	Wave /Z wST = $STwave
	Wave /Z wSTsweep = $STsweep
	Wave /Z wSTbin = $STwavebin
	
	//Bin and average the spike times

	variable j=0
	For (m=1;m<=NumSweeps;m+=1)
		NumPntsSweep =0

		For (i=0; i<NumPoints; i+= 1)
				
			If (wSTsweep[i]==m)
				NumPntsSweep +=  1
				wSTbin[j] += wST[i]
			Endif
		Endfor	

		If (NumPntsSweep>0)
			wSTbin[j]=wSTbin[j]/NumPntsSweep
		Else
			wSTbin[j]=NaN
		Endif
		j+=1
	Endfor
	
	If (cmpStr(ctrlName,"pAvgSpikes")==0)
			
		Display /N=SpikeNum_graph /W=(900,300,1400,500 ) /K=1 $STwavebin
		ModifyGraph mode=4,marker=19,rgb=(21845,21845,21845),useMrkStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "Average spike time for every "+num2str(bin)+"  spikes"
		Label bottom "Sweep #"

		SetDataFolder currentDF
	Else
		Return 1
	Endif
End

/////////////////////////////////////////////////////////////////////////////////////
//Instantaneous Frequency:Graph Control Panel
// Function: Inst_freq2
// Calculate instantaneous frequency and binned ISI summaries from a graph-derived ISI wave.
Function Inst_freq2(ctrlName):ButtonControl
	String ctrlName
	string valAsStr
	
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	variable j=0
	variable bin = 10
	Variable i,n

	Prompt bin, "What size bins?"
	DoPrompt "Analyze for instantaneous frequency", bin

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		//Get wave from wave in graph
		wave wave1 = WaveRefIndexed("",0,3)
		string inputname= NameofWave(wave1)	
		string dfinputname = GetWavesDataFolder(wave1,1)
		string inputwave = dfinputname+inputname
	
		String ISIwave = inputwave+"_ISI"
		Wave wISI = $ISIwave

		String instfreqwave = inputwave+"_freq"
		Make /O /N=(numpnts(wISI)) $instfreqwave
		Wave wInstfreq = $instfreqwave
	
		wInstfreq = 1/wISI
	
		String instfreqwaveavg = instfreqwave+num2str(bin)
		Make /O /N=(Ceil(numpnts(wInstfreq)/bin)) $instfreqwaveavg
		Wave wInstfreqavg = $instfreqwaveavg
		
		String isiwaveavg = ISIwave+num2str(bin)
		Make /O /N=(Ceil(numpnts(wISI)/bin)) $isiwaveavg
		Wave wIsiwaveavg = $isiwaveavg

		For (i=0; i<=(numpnts(wInstfreq)-bin); i+= bin)
			For (n=0; n<bin; n+=1)
				wInstfreqavg[j] += wInstfreq[i+n]
				wIsiwaveavg[j] += wISI[i+n]
			Endfor
			wInstfreqavg[j]=wInstfreqavg[j]/bin
			wIsiwaveavg[j]=wIsiwaveavg[j]/bin
			j+=1
		Endfor

		//calculate avg Inst Freq
		Variable pointnumber = numpnts(wInstfreq)
		Variable InstFreq_avg, ISI_avg
		For (i=0; i<pointnumber; i+= 1)
			InstFreq_avg += wInstfreq[i]
			ISI_avg += wISI[i]
		Endfor
		InstFreq_avg = (InstFreq_avg/pointnumber)
		sprintf valAsStr, "%.3g", InstFreq_avg
		InstFreq_avg= str2num(valAsStr)
		
		ISI_avg = ((ISI_avg/pointnumber)*1000)
		sprintf valAsStr, "%.3g", ISI_avg
		ISI_avg= str2num(valAsStr)
		
		//		Display /N=AvgInstFreq_graph /W=(900,300,1400,500 ) /K=1 $instfreqwaveavg 
		//		ModifyGraph mode=3,marker=19,rgb=(21845,21845,21845),useMrkStrokeRGB=1
		//		SetAxis/A/N=2 left
		//		TextBox/C/N=textbox1/A=MC /X=30.00/Y=-40.00 "Avg Inst Freq. = "+num2str(InstFreq_avg)+" Hz"
		
		Display /N=AvgISI_graph /W=(900,550,1400,750 ) /K=1 $isiwaveavg 
		ModifyGraph mode=3,marker=19,rgb=(21845,21845,21845),useMrkStrokeRGB=1
		SetAxis/A/N=2 left
		TextBox/C/N=textbox1/A=MC /X=30.00/Y=-40.00 "Avg  ISI = "+num2str(ISI_avg)+" ms"
	Endif

End


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//JT_extras Functions


////////////////////////////////////////////////////////////////////////////////////////////////////
//Find events resulting from direct stimulation of nerve fibers
// Function: Find_StimPeaks
// Detect directly evoked/stimulus-locked events within a fixed cursor window across sweeps.
Function Find_StimPeaks(ctrlName): ButtonControl
	string ctrlName
	string tempstring1
	string tempstring2
	string tempspikewave
	string SpikeTimewave
	string SpikeTimewavetemp
	string inputwave
	string accumwave
	string tempfolder1
	variable baseval
	variable tempwavenum1
	variable tempwavenum2
	variable i,xcsrA,xcsrB
	variable checknum

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
			
	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp

	NVAR a
	NVAR b 
	NVAR sweepStartnum
	NVAR c2 
	NVAR d		
	NVAR f
	
	SVAR FileNameTruncated
	
	If (f==0)
		DoAlert  0, "Must zero waves first"
		Zerosweeps("ctrlName",2)
	Endif
	
		
	//Create truncated name from tempwave
	tempwavenum1 = sweepStartnum
	tempwavenum2 = c2
	SpikeTimewavetemp = FileNameTruncated+"_temp"	
	SpikeTimewave = FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)+"_ST"
			
	If (WaveExists($SpikeTimewave)==1)
		KillWaves $SpikeTimewave
	Endif
		

	For (i=tempwavenum1; i<= tempwavenum2; i+=1)
		If (i==tempwavenum1)
			accumwave = FileNameTruncated+"_"+num2str(i)+input_type
			Display /N=Wave_Graph /W=(200,10,1200,610 ) /K=1 $accumwave as (accumwave+"to"+num2str(tempwavenum2))
			ModifyGraph rgb=(0,0,0)
			SetAxis/A/N=1/E=1 bottom
			SetAxis/A/N=2/E=0 left
			Label left "Current";DelayUpdate
			Label bottom "Time"
			SetAxis bottom 0.045,0.06
			Cursor A,  $accumwave,  0.0512
			Cursor B, $accumwave, 0.0525
			Showinfo
			xcsrA = xcsr(A)
			xcsrB = xcsr(B)
		Else
			accumwave = FileNameTruncated+"_"+num2str(i)+input_type
			AppendtoGraph $accumwave
			ModifyGraph rgb=(0,0,0)

		Endif
		
		tempspikewave = FileNameTruncated+"_"+num2str(i)+input_type
		Wave temp1 = $tempspikewave
		FindLevels /Q /B=20 /DEST=$SpikeTimewavetemp /EDGE=2 /M=(spiketime)/R=(xcsrA,xcsrB) temp1 eventamp
		concatenate /KILL {$SpikeTimewavetemp}, $SpikeTimewave
		
	Endfor
		
	
	Wave w1 = $SpikeTimewave
	w1 = w1-xcsrA  //normalize spike time to first x-cursor
	TextBox/C/N=textbox2/A=MC /X=20.00/Y=15.00 num2str(numpnts($SpikeTimewave))+" spikes"

	SetDataFolder root:$(tempfilefolder):$(tempfolder)

End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Play tone for every spike

// Function: Tone_Start
// Play a short tone at each ISI interval for auditory inspection of spike timing.
Function Tone_Start(ctrlName):ButtonControl
	string ctrlName	
	Variable ticktime
	Variable elapsetime
	Variable n
	Variable i
	
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave

	
	//Create truncated name from tempwave
	//Get wave from wave in graph
	wave wave1 = WaveRefIndexed("",0,3)
	string inputname= NameofWave(wave1)	
	string dfinputname = GetWavesDataFolder(wave1,1)
	string inputwave = dfinputname+inputname
	
	String ISIwave = inputwave+"_ISI"
	Wave wISI = $ISIwave
	

	Make/B/O/N=1000 sineSound			// 8 bit samples
	SetScale/P x,0,1e-6,sineSound		// Set sample rate
	sineSound= 100*sin(2*Pi*1000*x)	// Create sinewave tone

	For (i=0; i<numpnts(wISI); i+=1)
		ticktime=((wISI[i])*60.15) //converts to 60ths of a second for "ticks" timer
		elapsetime = ticks
		PlaySound sineSound

		do
		while (ticks<=elapsetime + ticktime)
	Endfor
	SetDataFolder root:$(tempfilefolder):$(tempfolder)
	Killwaves sineSound

End

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
//Generic Histogram analysis for WAVE of ISIs

// Function: CVwavestats
// Compute summary statistics and, optionally, a histogram for a selected wave.
Function CVwavestats (ctrlName)
	string ctrlName
	string histwave
	string inputwave
	string valAsStr

	variable binsize = 0.0005
	variable binnumber = 100
	variable binstart = 0.000
	variable pointnumber
	variable pointstart = 0
	variable tempnum1
	variable checknum
	variable i,j

	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
	Prompt tempnum1, "Histogram?", popup "yes;no"	
	DoPrompt "Select wave", inputwave,tempnum1
	If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
		abort
	Endif

	Wave wWave = $inputwave
	WaveTransform /O ZapNaNs wWave
	wavestats /Q wWave
	Printf "For %g events, the average spiketime is %.3g +/- %.3g\r", V_npnts,V_avg,V_sem
	Printf "The CV is %.3g\r",(V_sdev/V_avg)

	pointnumber = V_npnts
	sprintf valAsStr, "%.3g", V_avg
	Variable VAL_avg= str2num(valAsStr)

	sprintf valAsStr, "%.3g", V_sdev
	Variable VAL_sd= str2num(valAsStr)	
		

	//Prompt for Histogram values
	If (tempnum1==1)
		Prompt binsize, "Bin width:"
		Prompt binnumber, "Number of bins:"
		Prompt binstart, "Start bin at:"
		Prompt pointnumber, "Number of points to bin:"
		Prompt pointstart, "Start binning at point #:"
		DoPrompt "Create Histogram",binsize, binnumber, binstart, pointnumber, pointstart
	
		If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
			abort
		Endif

		histwave = inputwave+"_H" 
		Make /O /N=(binnumber) $histwave
		Histogram /R=[pointstart,pointnumber]/B={binstart,binsize,binnumber} $inputwave,$histwave
	
		//Display histo wave in new graph
		Display /N=hist_graph /W=(1000,600,1600,900 ) /K=1 $histwave
		ModifyGraph mode=5, rgb=(32768,32770,65535),hbFill=2,  useBarStrokeRGB=1

				
		Variable yMax = WaveMax ($histwave)
		FindValue /V=(yMax) $histwave
		ymax = pnt2X($histwave,V_value)
		Cursor A $histwave ymax
		Cursor /P B $histwave binnumber
		ShowInfo
		SetAxis /A/N=0/E=1 bottom
		Label left "Number of Events"
		Label bottom "Time (sec)"
		TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "mean = "+num2str(VAL_avg)+"\rC.V. = "+num2str(VAL_sd/VAL_avg)
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Average ISI values
// Function: avg_ISI
// Legacy helper for averaging ISI values over hard-coded time ranges in concatenated data.
Function avg_ISI (ctrlName)
	string ctrlName
	string SpikeTimewave
	string SpikeTimeWavebin
	string ISIwave
	string ISIwavebin
	string ISI_values
	SVAR FileNameTruncated
	
	variable i
	variable n
	variable m
	variable o
	

	Wave w0=$("root:A:Concat:"+FileNameTruncated+"_ST")
	Wave w1=$("root:A:Concat:"+FileNameTruncated+"_ISI")
	Wave w2 = $("root:A:Concat:"+FileNameTruncated+"_ISIb")
	Wave w3 = $("root:A:Concat:"+FileNameTruncated+"_STb")

	ISI_values = "root:A:Concat:"+FileNameTruncated+"_ISIvalues"
	Make /O/N=10 $ISI_values = 0
	Wave j = $ISI_values
	

	FindValue /T=0.5 /V=400 w0
	n = V_value
	FindValue /T=0.5 /V=500 w0
	m = V_value
	FindValue /T=0.5 /V=900 w0
	o = V_value
	print "Event # at 400s="+num2str(n),"Event # at 500s="+num2str(m),"Event # at 900s="+num2str(o) 
	For (i=0; i<n; i+= 1)
		j[0] += w1[i]
	Endfor
	j[1] = j[0]/n
	print "Avg ISI for events from 0 to 400s ="+num2str(j[1])

	For (i=m; i<o; i+= 1)
		j[2] += w1[i]
	Endfor
	j[3] = j[2]/(o-m)
	print "Avg ISI for events from 500 to 900s ="+num2str(j[3])

End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Averagre Period times for spikes
// Function: stimfreqstats
// Summarize vector-analysis waves from the current folder or all data folders.
Function stimfreqstats(ctrlName)
	String ctrlName
	String currentDF = GetDataFolder(1)	// Save
	Variable i, tempvar1,tempStat1,tempstat2,tempItems
	String vectorWaves

	Prompt tempvar1, "Select data:", popup "Current Folder; All Data Folders"
	DoPrompt "Select:", tempvar1
	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
	
		If (tempvar1==1)
			//These globals are within the current data folder:
			SVAR FileNameTruncated
			String tempFilename = FileNameTruncated
		Endif
	
	
		String tempFolder= "root:A:V"
		SetDataFolder tempFolder

		String AvgVarianceWave = "AvgVarianceWave"
		String AvgPeriodWave = "AvgPeriodWave"


		If(tempvar1==1)
			String tempWaves=WaveList(tempFilename+"*",";","") // A list of V from current graph only
			vectorWaves = ListMatch(tempWaves,"*_V")
			tempItems = itemsinlist(vectorWaves)
		Else
			vectorWaves=WaveList("*_V",";","") // A list of all graphs
			tempItems = itemsinlist(vectorWaves)
		Endif
		If (tempItems==0)
			SetDataFolder currentDF
			Abort "No vector analysis associated with graph(s)"
		Endif
		
		Make /O /N=(tempItems) $AvgPeriodWave = 0
		Wave aWave = $AvgPeriodWave
		Make /O /N=(tempItems) $AvgVarianceWave = 0
		Wave bWave = $AvgVarianceWave
		For(i=0;i<tempItems;i+=1)
			string tempwave=stringfromlist(i,vectorWaves)
			string tempdestwave = tempwave+"o"
			Duplicate /O $tempwave $tempdestwave
			Wave cWave = $tempdestwave
			//cWave = bWave-wavemin(bWave)
			tempStat1 = mean($tempdestwave)
			tempStat2 = variance($tempdestwave)
			aWave[i] = tempStat1
			bWave[i] = tempStat2

			CVwavestats(tempdestwave)
		Endfor
	
		If(tempvar1==1)
			Print "For "+vectorWaves+" the mean spiketime is "+num2str(tempStat1)
			Print "and the variance is "+num2str(tempStat2)		
		Else		
			wavestats /Q aWave
			Print "For "+num2str(V_npnts)+" events, the average spiketime is "+num2str(V_avg)+" +/- "+num2str(V_sem)

			wavestats /Q bWave
			Print "and the average variance is "+num2str(V_avg)+" +/- "+num2str(V_sem)
		Endif
		
		SetDataFolder currentDF
	Endif

End


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Calulate Vector strength from every data folder in file 08/17/2012 JGT

// Function: VectorfromGraphs
// Batch vector-strength analysis across folders listed in root:Packages:MPVars:RootFolder_list.
Function VectorfromGraphs(ctrlName,ctrlNum)

	String ctrlName
	Variable ctrlNum

	string cmd
	string vectorwave,Avectorwave,Bvectorwave,Cvectorwave,Dvectorwave
	string sumvectorwave,sumAvectorwave,sumBvectorwave,sumCvectorwave,sumDvectorwave
	string vectorwavex,Avectorwavex,Bvectorwavex,Cvectorwavex,Dvectorwavex
	string sumvectorwavex,sumAvectorwavex,sumBvectorwavex,sumCvectorwavex,sumDvectorwavex
	string vectorwavey,Avectorwavey,Bvectorwavey,Cvectorwavey,Dvectorwavey
	string sumvectorwavey,sumAvectorwavey,sumBvectorwavey,sumCvectorwavey,sumDvectorwavey
	string vectorwavehist,Avectorwavehist,Bvectorwavehist,Cvectorwavehist,Dvectorwavehist,BDvectorwavehist
	String latencyList,AlatencyList,BlatencyList,ClatencyList,DlatencyList 
	String inputname
	String inputwave
	String tempDF
	String tempFullDF
	String tempRootDF
	string valAsStr
	string matchStr,matchStrA,matchStrB,matchStrC,matchStrD
	string accumwaveA,accumwaveB,accumwaveC,accumwaveD
	string VH_graph,AVH_graph,BVH_graph,CVH_graph,DVH_graph
	
	
	SVAR RootFolder_list = root:Packages:MPVars:RootFolder_list
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	NVAR tempfreq = root:A:tempfreq
	
	variable f =tempfreq
	variable sumvectorstrength,sumAvectorstrength,sumBvectorstrength,sumCvectorstrength,sumDvectorstrength
	variable vectorstrength,Avectorstrength,Bvectorstrength,Cvectorstrength,Dvectorstrength
	variable vectorstrengthround,Avectorstrengthround,Bvectorstrengthround,Cvectorstrengthround,Dvectorstrengthround
	variable accumWavepoints
	variable n,i,j, index
	variable bins = 50
	variable binwidth = 1/bins
	variable tempNum1, vector,Avector,Bvector,Cvector,Dvector


	If (ctrlNum==1)
		vectorwavehist = "root:A:V:Vector1Hist"
		Avectorwavehist = "root:A:V:A1_VectorHist"
		Bvectorwavehist = "root:A:V:B1_VectorHist"
		Cvectorwavehist = "root:A:V:sweepStartnum_VectorHist"
		Dvectorwavehist = "root:A:V:D1_VectorHist"
		BDvectorwavehist = "root:A:V:BD1_VectorHist"
	Else
		vectorwavehist = "root:A:V:VectorHist"
		Avectorwavehist = "root:A:V:A_VectorHist"
		Bvectorwavehist = "root:A:V:B_VectorHist"
		Cvectorwavehist = "root:A:V:C_VectorHist"
		Dvectorwavehist = "root:A:V:D_VectorHist"
		BDvectorwavehist = "root:A:V:BD_VectorHist"
		
	Endif
	
	Make /O /N=(bins) $vectorwavehist
	Make /O /N=(bins) $Avectorwavehist
	Make /O /N=(bins) $Bvectorwavehist
	Make /O /N=(bins) $Cvectorwavehist
	Make /O /N=(bins) $Dvectorwavehist
	Make /O /N=(bins) $BDvectorwavehist


	For(n=0;n<itemsinlist(RootFolder_list);n+=1)

		If (itemsinlist(RootFolder_list)==0)
			Abort "No Data Folders"
		Endif

		tempRootDF = "root:"+stringfromlist(n,RootFolder_list)

		String ListofFolderNames=""
		String Foldername=""	
		index=0
		Do
			Foldername = GetIndexedObjName(tempRootDF,4, index)
			if (strlen(Foldername) == 0)
				break
			endif
			ListofFolderNames+=Foldername+";"
			index+=1
		While(1)

		If (itemsinlist(ListofFolderNames)==0)
			SetDataFolder root:$(tempfilefolder):$(tempfolder)
			Abort "No Data Folders in "+tempRootDF
		Endif

		For(i=0;i<itemsinlist(ListofFolderNames);i+=1)
		
			tempDF = stringfromlist(i,ListofFolderNames)
		
			tempFullDF = tempRootDF+":"+tempDF

			SetDataFolder tempFullDF
			
			//*************************
			//For all waves
			//Strings for the vector waves
			//Name according to 1st spike or all spike values
			If (ctrlNum==1)
				vectorwave = "root:A:V:"+tempDF+"V1"
				Avectorwave = "root:A:V:"+tempDF+"A1_V"
				Bvectorwave = "root:A:V:"+tempDF+"B1_V"
				Cvectorwave = "root:A:V:"+tempDF+"sweepStartnum_V"
				Dvectorwave = "root:A:V:"+tempDF+"D1_V"
			
				sumvectorwave = "root:A:V:sumVectorV1"
				sumAvectorwave = "root:A:V:sumVectorA1_V"
				sumBvectorwave = "root:A:V:sumVectorB1_V"
				sumCvectorwave = "root:A:V:sumVectorsweepStartnum_V"
				sumDvectorwave = "root:A:V:sumVectorD1_V"
			Else
			
				vectorwave = "root:A:V:"+tempDF+"V"
				Avectorwave = "root:A:V:"+tempDF+"A_V"
				Bvectorwave = "root:A:V:"+tempDF+"B_V"
				Cvectorwave = "root:A:V:"+tempDF+"C_V"
				Dvectorwave = "root:A:V:"+tempDF+"D_V"
			
				sumvectorwave = "root:A:V:sumVectorV"
				sumAvectorwave = "root:A:V:sumVectorA_V"
				sumBvectorwave = "root:A:V:sumVectorB_V"
				sumCvectorwave = "root:A:V:sumVectorC_V"
				sumDvectorwave = "root:A:V:sumVectorD_V"
			
			Endif

			vectorwavex = "root:A:V:"+tempDF+"X"
			vectorwavey = "root:A:V:"+tempDF+"Y"
			Avectorwavex = "root:A:V:"+tempDF+"A_X"
			Avectorwavey = "root:A:V:"+tempDF+"A_Y"
			Bvectorwavex = "root:A:V:"+tempDF+"B_X"
			Bvectorwavey = "root:A:V:"+tempDF+"B_Y"
			Cvectorwavex = "root:A:V:"+tempDF+"C_X"
			Cvectorwavey = "root:A:V:"+tempDF+"C_Y"
			Dvectorwavex = "root:A:V:"+tempDF+"D_X"
			Dvectorwavey = "root:A:V:"+tempDF+"D_Y"

			sumvectorwavex = "root:A:V:sumVectorVx"
			sumvectorwavey = "root:A:V:sumVectorVy"
			sumAvectorwavex = "root:A:V:sumVectorA_Vx"
			sumBvectorwavex = "root:A:V:sumVectorB_Vx"
			sumCvectorwavex = "root:A:V:sumVectorC_Vx"
			sumDvectorwavex = "root:A:V:sumVectorD_Vx"	
			sumAvectorwavey = "root:A:V:sumVectorA_Vy"
			sumBvectorwavey = "root:A:V:sumVectorB_Vy"
			sumCvectorwavey = "root:A:V:sumVectorC_Vy"
			sumDvectorwavey = "root:A:V:sumVectorD_Vy"			
			

			If (ctrlNum==1)
				matchStr = "*_L1*"
				matchstrA = "*_L1_AB"
				matchstrB = "*_L1_BC"
				matchstrC = "*_L1_CD"
				matchstrD = "*_L1_DE"
			
			Else
				matchStr = "*_L*"
				matchstrA = "*_L_AB"
				matchstrB = "*_L_BC"
				matchstrC = "*_L_CD"
				matchstrD = "*_L_DE"

			Endif
			
			latencyList = WaveList(matchStr, ";", "")
			If (itemsinlist(latencyList)>0)

				Concatenate /NP latencyList, $sumvectorwave
				Concatenate /NP latencyList, $sumvectorwavex
				Concatenate /NP latencyList, $sumvectorwavey
				Concatenate /NP latencyList, $vectorwave
				Concatenate /NP latencyList, $vectorwavex
				Concatenate /NP latencyList, $vectorwavey		
				Wave v = $vectorwave
				Wave vx = $vectorwavex
				Wave vy = $vectorwavey
			Endif

			AlatencyList = WaveList(matchstrA, ";", "")
			If (itemsinlist(AlatencyList)>0)

				Concatenate /NP AlatencyList, $sumAvectorwave
				Concatenate /NP AlatencyList, $sumAvectorwavex
				Concatenate /NP AlatencyList, $sumAvectorwavey
				Concatenate /NP AlatencyList, $Avectorwave
				Concatenate /NP AlatencyList, $Avectorwavex
				Concatenate /NP AlatencyList, $Avectorwavey		
				Wave Av = $Avectorwave
				Wave Avx = $Avectorwavex
				Wave Avy = $Avectorwavey
			Endif

			BlatencyList = WaveList(matchstrB, ";", "")
			If (itemsinlist(BlatencyList)>0)

				Concatenate /NP BlatencyList, $sumBvectorwave
				Concatenate /NP BlatencyList, $sumBvectorwavex
				Concatenate /NP BlatencyList, $sumBvectorwavey
				Concatenate /NP BlatencyList, $Bvectorwave
				Concatenate /NP BlatencyList, $Bvectorwavex
				Concatenate /NP BlatencyList, $Bvectorwavey		
				Wave Bv = $Bvectorwave
				Wave Bvx = $Bvectorwavex
				Wave Bvy = $Bvectorwavey
			Endif

			ClatencyList = WaveList(matchstrC, ";", "")
			If (itemsinlist(ClatencyList)>0)

				Concatenate /NP ClatencyList, $sumCvectorwave			
				Concatenate /NP ClatencyList, $sumCvectorwavex
				Concatenate /NP ClatencyList, $sumCvectorwavey
				Concatenate /NP ClatencyList, $Cvectorwave
				Concatenate /NP ClatencyList, $Cvectorwavex
				Concatenate /NP ClatencyList, $Cvectorwavey		
				Wave Cv = $Cvectorwave
				Wave Cvx = $Cvectorwavex
				Wave Cvy = $Cvectorwavey
			Endif

			DlatencyList = WaveList(matchstrD, ";", "")
			If (itemsinlist(DlatencyList)>0)

				Concatenate /NP DlatencyList, $sumDvectorwave
				Concatenate /NP DlatencyList, $sumDvectorwavex
				Concatenate /NP DlatencyList, $sumDvectorwavey
				Concatenate /NP DlatencyList, $Dvectorwave
				Concatenate /NP DlatencyList, $Dvectorwavex
				Concatenate /NP DlatencyList, $Dvectorwavey		
				Wave Dv = $Dvectorwave
				Wave Dvx = $Dvectorwavex
				Wave Dvy = $Dvectorwavey
			Endif

			//If data folder is empty of Latency waves, then skip to next data folder
			If  (itemsinlist(latencyList)>0)
				tempNum1+=1
				//Transform latency to values within a single cycle with Y=(Y/(1000/60))-floor(Y/(1000/60)); 1000 is for ISI in ms
				v = (v/(1/f))-floor(v/(1/f))
				Av = (Av/(1/f))
				Bv = (Bv/(1/f))
				Cv = (Cv/(1/f))
				Dv = (Dv/(1/f))
		
				//1st: transform the latency floors to radians then: unit vector angles with x (use cosine) and y (use sine) coordinates
				vx = cos(2*pi*v)
				Avx = cos(2*pi*Av)
				Bvx = cos(2*pi*Bv)
				Cvx = cos(2*pi*Cv)
				Dvx = cos(2*pi*Dv)
				
				vy = sin(2*pi*v)
				Avy = sin(2*pi*Av)
				Bvy = sin(2*pi*Bv)
				Cvy = sin(2*pi*Cv)
				Dvy = sin(2*pi*Dv)
		
		
				//sum of vector x and y : SQRT(POWER(B2,2)+POWER(C2,2))/D2
				vectorstrength = sqrt(     (sum(vx))^2      +     (sum(vy))^2     )            /numpnts(v)
				Avectorstrength = sqrt((sum(Avx))^2+(sum(Avy))^2)/numpnts(Av)
				Bvectorstrength = sqrt((sum(Bvx))^2+(sum(Bvy))^2)/numpnts(Bv)
				Cvectorstrength = sqrt((sum(Cvx))^2+(sum(Cvy))^2)/numpnts(Cv)
				Dvectorstrength = sqrt((sum(Dvx))^2+(sum(Dvy))^2)/numpnts(Dv)

			
				//			vector +=vectorstrength
				//			Avector +=Avectorstrength
				//			Bvector +=Bvectorstrength
				//			Cvector +=Cvectorstrength
				//			Dvector +=Dvectorstrength
					
				//AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
				//Make the vector wave for A deflections
				If (ctrlNum==1)
					accumwaveA= "root:A:Avg:Vectorvalues_A1"
				Else
					accumwaveA= "root:A:Avg:Vectorvalues_A"
				Endif
									
				If (Exists(accumwaveA)==0)
					Make /O /N=(0) $accumwaveA
				Endif					
				WAVE wAccumA=$(accumwaveA)

				//Count the number of values in the accum wave
				accumWavepoints = numpnts (wAccumA)
				InsertPoints /M=0 accumWavepoints, 1, wAccumA //add a slot for the new latency value
				wAccumA[accumWavepoints]=Avectorstrength
	
				//BBBBBBBBBBBBBBBBBBBBBBBBBBBBBB
				//Make the vector wave for B deflections
				If (ctrlNum==1)
					accumwaveB= "root:A:Avg:Vectorvalues_B1"
				Else
					accumwaveB= "root:A:Avg:Vectorvalues_B"
				Endif
									
				If (Exists(accumwaveB)==0)
					Make /O /N=(0) $accumwaveB
				Endif					
				WAVE wAccumB=$(accumwaveB)

				//Count the number of values in the accum wave
				accumWavepoints = numpnts (wAccumB)
				InsertPoints /M=0 accumWavepoints, 1, wAccumB //add a slot for the new latency value
				wAccumB[accumWavepoints]=Bvectorstrength
	
				//CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC
				//Make the vector wave for C deflections
				If (ctrlNum==1)
					accumwaveC= "root:A:Avg:Vectorvalues_sweepStartnum"
				Else
					accumwaveC= "root:A:Avg:Vectorvalues_C"
				Endif				
				If (Exists(accumwaveC)==0)
					Make /O /N=(0) $accumwaveC
				Endif					
				WAVE wAccumC=$(accumwaveC)

				//Count the number of values in the accum wave
				accumWavepoints = numpnts (wAccumC)
				InsertPoints /M=0 accumWavepoints, 1, wAccumC //add a slot for the new latency value
				wAccumC[accumWavepoints]=Cvectorstrength
	
				//DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
				//Make the vector wave for D deflections
				If (ctrlNum==1)
					accumwaveD= "root:A:Avg:Vectorvalues_D1"
				Else
					accumwaveD= "root:A:Avg:Vectorvalues_D"
				Endif				
				If (Exists(accumwaveD)==0)
					Make /O /N=(0) $accumwaveD
				Endif					
				WAVE wAccumD=$(accumwaveD)

				//Count the number of values in the accum wave
				accumWavepoints = numpnts (wAccumD)
				InsertPoints /M=0 accumWavepoints, 1, wAccumD //add a slot for the new latency value
				wAccumD[accumWavepoints]=Dvectorstrength

				If (ctrlNum==1)
					Print "Cell #:,"+num2str(tempnum1)+", Avg 1st spike Vector:,"+num2str(vectorstrength)+", 1st spike from A_Vector:,"+num2str(Avectorstrength)+", 1st spike from B_Vector:,"+num2str(Bvectorstrength)+", 1st spike from C_Vector:,"+num2str(Cvectorstrength)+", 1st spike from D_Vector:,"+num2str(Dvectorstrength)
				Else
					Print "Cell #:,"+num2str(tempnum1)+", Avg Vector:,"+num2str(vectorstrength)+", A Vector:,"+num2str(Avectorstrength)+", B Vector:,"+num2str(Bvectorstrength)+", C Vector:,"+num2str(Cvectorstrength)+", D Vector:,"+num2str(Dvectorstrength)
				Endif
				
				KillWaves vx, vy,Avx, Avy,Bvx, Bvy,Cvx, Cvy,Dvx, Dvy
			
				If ((i==0)&&(n==0))
					Histogram /B={0,binwidth,bins} /C /R=(0) $vectorwave, $vectorwavehist
					Histogram /B={0,binwidth,bins} /C /R=(0) $Avectorwave, $Avectorwavehist
					Histogram /B={0,binwidth,bins} /C /R=(0) $Bvectorwave, $Bvectorwavehist
					Histogram /B={0,binwidth,bins} /C /R=(0) $Cvectorwave, $Cvectorwavehist
					Histogram /B={0,binwidth,bins} /C /R=(0) $Dvectorwave, $Dvectorwavehist
				Else //accumulate
					Histogram /A /B={0,binwidth,bins} /C /R=(0) $vectorwave, $vectorwavehist
					Histogram /A /B={0,binwidth,bins} /C /R=(0) $Avectorwave, $Avectorwavehist
					Histogram /A /B={0,binwidth,bins} /C /R=(0) $Bvectorwave, $Bvectorwavehist
					Histogram /A /B={0,binwidth,bins} /C /R=(0) $Cvectorwave, $Cvectorwavehist
					Histogram /A /B={0,binwidth,bins} /C /R=(0) $Dvectorwave, $Dvectorwavehist

				Endif
				//*************************
			Endif
		Endfor
	Endfor

	
	//LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL	
	//LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL	
	Wave sumv = $sumvectorwave
	Wave sumvx = $sumvectorwavex
	Wave sumvy = $sumvectorwavey

	Wave sumAv = $sumAvectorwave
	Wave sumAvx = $sumAvectorwavex
	Wave sumAvy = $sumAvectorwavey

	Wave sumBv = $sumBvectorwave
	Wave sumBvx = $sumBvectorwavex
	Wave sumBvy = $sumBvectorwavey

	Wave sumCv = $sumCvectorwave
	Wave sumCvx = $sumCvectorwavex
	Wave sumCvy = $sumCvectorwavey

	Wave sumDv = $sumDvectorwave
	Wave sumDvx = $sumDvectorwavex
	Wave sumDvy = $sumDvectorwavey

	sumv = (sumv/(1/f))-floor(sumv/(1/f)) //subtract floor to normalize to deflections B,C, and D
	sumAv = (sumAv/(1/f))
	sumBv = (sumBv/(1/f))
	sumCv = (sumCv/(1/f))
	sumDv = (sumDv/(1/f))
			
	//1st: transform the latency floors to radians then: unit vector angles with x (use cosine) and y (use sine) coordinates
	sumvx = cos(2*pi*sumv) //this calculates the x-length of a unit vector of angle "v" in radians
	sumAvx = cos(2*pi*sumAv)
	sumBvx = cos(2*pi*sumBv)
	sumCvx = cos(2*pi*sumCv)
	sumDvx = cos(2*pi*sumDv)
				
	sumvy = sin(2*pi*sumv)
	sumAvy = sin(2*pi*sumAv)
	sumBvy = sin(2*pi*sumBv)
	sumCvy = sin(2*pi*sumCv)
	sumDvy = sin(2*pi*sumDv)
		
		
	//sum of vector x and y : SQRT(POWER(B2,2)+POWER(C2,2))/D2
	sumvectorstrength = sqrt(     (sum(sumvx))^2      +     (sum(sumvy))^2     )            /numpnts(sumv)
	sumAvectorstrength = sqrt((sum(sumAvx))^2+(sum(sumAvy))^2)/numpnts(sumAv)
	sumBvectorstrength = sqrt((sum(sumBvx))^2+(sum(sumBvy))^2)/numpnts(sumBv)
	sumCvectorstrength = sqrt((sum(sumCvx))^2+(sum(sumCvy))^2)/numpnts(sumCv)
	sumDvectorstrength = sqrt((sum(sumDvx))^2+(sum(sumDvy))^2)/numpnts(sumDv)
			
	KillWaves sumvx, sumvy,sumAvx,sumAvy,sumBvx,sumBvy,sumCvx,sumCvy,sumDvx,sumDvy
			
	If (ctrlNum==1)
		Print "Avg 1st spike Vector:,"+num2str(sumvectorstrength)+", 1st spike A_Vector:,"+num2str(sumAvectorstrength)+", 1st spike B_Vector:,"+num2str(sumBvectorstrength)+", 1st spike C_Vector:,"+num2str(sumCvectorstrength)+", 1st spike D_Vector:,"+num2str(sumDvectorstrength)
	Else
		Print "Avg Vector:,"+num2str(sumvectorstrength)+", A Vector:,"+num2str(sumAvectorstrength)+", B Vector:,"+num2str(sumBvectorstrength)+", C Vector:,"+num2str(sumCvectorstrength)+", D Vector:,"+num2str(sumDvectorstrength)

	Endif
	//LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL	
	//LLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLLL	
		

	sprintf valAsStr, "%.3g", sumvectorstrength
	sumvectorstrength= str2num(valAsStr)
	
	sprintf valAsStr, "%.3g", sumAvectorstrength
	sumAvectorstrength= str2num(valAsStr)
		
	sprintf valAsStr, "%.3g", sumBvectorstrength
	sumBvectorstrength= str2num(valAsStr)
		
	sprintf valAsStr, "%.3g", sumCvectorstrength
	sumCvectorstrength= str2num(valAsStr)
		
	sprintf valAsStr, "%.3g", sumDvectorstrength
	sumDvectorstrength= str2num(valAsStr)
	
	//Display average wave
	//SetDataFolder root:A:V:
	//fWaveAverage(WaveList("*V",";", ""),"", 1, 3, "AvgVector", "AvgVector_Nsd")
	//Display/K=1 /W=(900,550,1400,750 ) root:A:V:AvgVector
	//ModifyGraph mode=3,marker=19,rgb=(0,0,0),useMrkStrokeRGB=1
	//ErrorBars AvgVector Y,wave=(root::A:V:AvgVector_Nsd,root:A:V:AvgVector_Nsd)

	If (ctrlNum==1)
		VH_graph = "AD1_Hist"
		AVH_graph = "A1_Hist"
		BVH_graph = "B1_Hist"
		CVH_graph = "sweepStartnum_Hist"
		DVH_graph = "D1_Hist"
	Else
		VH_graph = "AD_Hist"
		AVH_graph = "A_Hist"
		BVH_graph = "B_Hist"
		CVH_graph = "C_Hist"
		DVH_graph = "D_Hist"
	Endif		
	
	Display /N=$(VH_graph) /W=(900,050,1400,200 ) /K=1 $vectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(21845,21845,21845)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"
	TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg vector strength = "+num2str(sumvectorstrength)+" (n="+num2str(tempNum1)+")"

	Display /N=$(AVH_graph) /W=(900,250,1400,400 ) /K=1 $Avectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(52428,1,1)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"
	TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg vector strength = "+num2str(sumAvectorstrength)+" (n="+num2str(tempNum1)+")"

	Display /N=$(BVH_graph) /W=(900,450,1400,600 ) /K=1 $Bvectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(1,4,52428)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"
	TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg vector strength = "+num2str(sumBvectorstrength)+" (n="+num2str(tempNum1)+")"

	Display /N=$(CVH_graph) /W=(900,650,1400,800 ) /K=1 $Cvectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(1,26214,0)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"
	TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg vector strength = "+num2str(sumCvectorstrength)+" (n="+num2str(tempNum1)+")"

	Display /N=$(DVH_graph) /W=(900,850,1400,1000 ) /K=1 $Dvectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(65535,43690,0)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"
	TextBox/C/N=textbox1/A=MC /X=30.00/Y=-15.00 "Avg vector strength = "+num2str(sumDvectorstrength)+" (n="+num2str(tempNum1)+")"

	
	
	////Plot histogram of sum of B through D historgrams
	WAVE BDWave = $BDVectorwavehist
	WAVE BWave = $Bvectorwavehist
	WAVE CWave = $Cvectorwavehist
	WAVE DWave = $Dvectorwavehist

	For(i=0;i<bins;i+=1)

		BDWave [i]= BWave[i]+CWave[i]+DWave[i]
	endfor

	Display /N=BDVectorHist_graph /W=(1400,850,1900,1000 ) /K=1 $BDvectorwavehist
	ModifyGraph mode=5,useBarStrokeRGB=1, hbFill=2,rgb=(39321,26208,1)
	SetAxis/A/N=0/E=1 bottom
	SetAxis/A/N=1/E=1 left
	Label left "# of Events"
	Label bottom "Unit Cycle"+" ("+num2str(f)+"Hz)"

	//Make a table with all the individual vector strengths
	If (ctrlNum==1)
		Edit /K=1 /N=Total1stVectors $(accumwaveA),$(accumwaveB),$(accumwaveC),$(accumwaveD) as "Vector Strengths for 1st spikes from each cell"
	Else
		Edit /K=1 /N=TotalVectors $(accumwaveA),$(accumwaveB),$(accumwaveC),$(accumwaveD) as "Vector Strengths for all spikes from each cell"
	Endif
	
	SetDataFolder root:$(tempfilefolder):$(tempfolder)
End


//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///

// Function: recurrencePlot
// Display recurrence plots for one ISI wave or all ISI waves in the current context.
Function recurrencePlot(tempstring,tempnum1,tempnum2)
	String tempstring
	Variable tempnum1,tempnum2
	String inputname
	Variable pointnumber	
	Variable j

	String inputwaveList 
	String currentDFR = GetDataFolder(0)
	
	If (tempnum1==1)

		If (tempnum2==-1)
			tempnum2=1
			Prompt tempstring, "Please choose a wave:", popup WaveList("*",";","")
			Prompt tempnum2, "Please choose a non-negative offset value for recurrence plot:"
			DoPrompt "Rcurrence Plot", tempstring,tempnum2
			If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
				Abort
			Endif
		
		Endif
		
		inputname = tempstring
		
		pointnumber = DimSize($inputname,0)


		//Offset X from Y (ISI wave)
		Display /N=ISI_graph /K=1 /W=(600,480,1000,700 ) $inputname[0,pointnumber-tempnum2-1] vs $inputname[tempnum2,pointnumber-1]
		ModifyGraph mode=3,marker=8,msize=2,rgb=(0,0,0),useMrkStrokeRGB=1
		ModifyGraph log=1	
	
	Else


		If (cmpstr(currentDFR,"root")==0)
			inputwaveList = WaveList("*", ";", "")
		Else		
			inputwaveList = WaveList("*_ISI", ";", "")
		Endif

		For(j=0;j<itemsinlist(inputwaveList);j+=1)
			inputname=stringfromlist(j,inputwaveList)
	 
			pointnumber = DimSize($inputname,0)


			//Offset X from Y (ISI wave)
			Display /N=ISI_graph /K=1 /W=(600,480,1000,700 ) $inputname[0,pointnumber-tempnum2-1] vs $inputname[tempnum2,pointnumber-1]
			ModifyGraph mode=3,marker=8,msize=2,rgb=(0,0,0),useMrkStrokeRGB=1
			ModifyGraph log=1
		Endfor


		String info = IgorInfo(0)
		String screen1RectStr = StringByKey("SCREEN1", info)		//e.g., "DEPTH=23,RECT=0,0,1280,1024"
		Variable depth, left, top, right, bottom
		sscanf screen1RectStr, "DEPTH=%d,RECT=%d,%d,%d,%d", depth, left,top, right, bottom

		String cmd
		sprintf cmd, "TileWindows/O=%d/W=(%d,%d,%d,%d)", 1,0.1*right,0.01*bottom,0.8*right,0.8*bottom
		Execute cmd
	Endif
End
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//Code from Razina and Andrew
// Function: findLatDiff
// Measure first-to-second spike latency differences within each sweep.
Function findLatDiff(ctrlName)
	String ctrlName
	SVAR /Z input_type = root:A:input_type		
	NVAR /Z sweepStartnum = root:A:sweepStartnum
	NVAR /Z sweepEndnum = root:A:sweepEndnum
	NVAR /Z sweepCurrent = root:A:sweepCurrent		
	
	SVAR /Z FileNameTruncated


	//Input file names
	String sweepNumberWave
	String latencyWave
	String fileName = FileNameTruncated+"_latDiff"

	Variable sweepnum = sweepEndnum-sweepStartnum+1
	Variable n =sweepnum-1

	Prompt sweepNumberWave, "Wave with Sweep Numbers", popup WaveList("*_ST_*_swp",";","")
	Prompt latencyWave, "Wave with Latency Times", popup WaveList("*_L_*", ";", "")
	Prompt fileName, "Output latency difference file name"
	DoPrompt "Select Wave to be Analyzed", sweepNumberWave, latencyWave, fileName

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		//Make waves
		Wave WsweepNum = $sweepNumberWave
		Wave latency = $latencyWave
		Make /O /N=(sweepnum) $fileName
		Wave W_latDifference = $fileName

		variable totalPoints = numpnts(WsweepNum) //tells you the number of points in RAB0720132_3_1to60_ST_AB_sweep wave
		variable differenceIndex = 0 //says which spot in wave "latDifference" the new latency difference should go into
		variable index = 0 

		Do //do the comparisons
			if(index == 0 || WsweepNum[index] != WsweepNum[index-1]) //First sweep or found difference in sweeps
				if(WsweepNum[index] == WsweepNum[index +1]) //Same sweep
					W_latDifference[differenceIndex] = latency[index + 1]-latency[index]
					differenceIndex += 1
				Endif
			Endif
			index += 1
		While (index < totalPoints -1) //stops the loop from running when we've compared all the index points

		//Delete zeros
		Do
			If (W_latDifference[n]==0)
				DeletePoints n, 1, W_latDifference
			Endif
			n=n-1
		While (n>=0)

		
		Display /N=$fileName /W=(350,550,850,750 ) /K=1 $fileName
		ModifyGraph mode=3,marker=19,useMrkStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom
		SetAxis/A/N=2/E=1 left
		Label left "Latency from 1st spike to 2nd (s)";DelayUpdate
		Label bottom "Event #"
		
		If (numpnts(W_latDifference)>0)
			wavestats /Q W_latDifference

			Variable vMin = 1000*V_min
			String valAsStr
			sprintf valAsStr, "%.3g", vMin
			vMin= str2num(valAsStr)

			Variable vMax = 1000*V_max
			sprintf valAsStr, "%.3g", vMax
			vMax= str2num(valAsStr)

			Variable Vnpnts = V_npnts
			sprintf valAsStr, "%.3g", Vnpnts
			Vnpnts= str2num(valAsStr)

			Variable Vavg = 1000*V_avg
			sprintf valAsStr, "%.3g", Vavg
			Vavg= str2num(valAsStr)

			Variable Vsem = 1000*V_sem
			sprintf valAsStr, "%.3g", Vsem
			Vsem= str2num(valAsStr)

			Variable Vsdev = 1000*V_sdev
			sprintf valAsStr, "%.3g", Vsdev
			Vsdev= str2num(valAsStr)

			Variable Vcv = NaN
			If (Vavg!=0)
				Vcv = Vsdev/Vavg
			Endif
			sprintf valAsStr, "%.3g", Vcv
			Vcv= str2num(valAsStr)
		
		Endif
		
		String topGraph = WinName(0, 1)	// Name of top graph
		TextBox /W=$topGraph  /A=LT /N=textbox1 /X=0 /Y=-3 /F=0 "\\Z10Shortest = " + num2str(Vmin) + " msec\rMean = " + num2str(Vavg) + " msec\rCV = " + num2str(Vcv)
		//SetDrawLayer UserFront
		SetDrawEnv /W=$topGraph xcoord= prel,ycoord= left, linefgc= (65535,0,0), dash=1
		DrawLine /W=$topGraph 0,(mean(W_latDifference)),1,(mean(W_latDifference))

		String nb0 = "Statistics"
		String nb_list=WinList(nb0,";","WIN:16")
		If (cmpstr(nb_list,"")==0)
			Print "Average 1,2-ISI = "+num2str(Vavg)+" ± "+num2str(Vsem)+" SEM"
		Else
			Notebook $nb0 text= "Average 1,2-ISI = "+num2str(Vavg)+" ± "+num2str(Vsem)+" SEM\r"
		Endif



		//	Printf "For %g events, the shortest spiketime is %.3g\r", V_npnts,V_min
		//	Printf "The average spiketime is %.3g +/- %.3g\r", V_avg,V_sem
		//	Printf "The CV is %.3g\r",(V_sdev/V_avg)
	
		
	Endif //DoPrompt
End
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
// Function: colorizeSpiketimes
// Create/append a raster-like graph with spike order encoded by color.
Function colorizeSpiketimes(ctrlName)
	String ctrlName

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	String currentDFR = GetDataFolder(0)
	
	String sweepNumberWave
	String latencyWave
	String SpikeperSweep_graph
	Variable tempVal1

	Prompt sweepNumberWave, "Wave with Sweep Numbers", popup WaveList("*_ST_*_swp",";","")
	Prompt latencyWave, "Wave with Spike Times", popup WaveList("*_ST_*", ";", "")
	Prompt tempVal1, "Append to colorized graph?", popup ("no;yes")
	DoPrompt "Select Waves to be Analyzed", sweepNumberWave, latencyWave, tempVal1

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		WAVE Y_wave = $sweepNumberWave
		WAVE Z_wave = $latencyWave
		Variable numpoints = numpnts (Y_wave)
		Variable numsweeps = wavemax (Y_wave)
		Variable i,n, m

		//If (tempVal1==1)
		//SpikeperSweep_graph = nameofwave(Z_wave)+"_graph"
		//Else
		SpikeperSweep_graph = "Colorizedspikegraph"
		//Endif		
	
		ColorTab2Wave Landandsea8
		WAVE/Z colorWave = M_colors		// Created by ColorTab2Wave; needed as a wave reference under rtGlobals=3.

		String newNumWave = sweepNumberWave+"2"
		Duplicate /O Y_Wave $newNumWave
		WAVE/Z Y_wave2 =  $newNumWave
		If (!WaveExists(Y_wave2) || !WaveExists(colorWave))
			Abort "Could not create the spike-color waves for colorizeSpiketimes."
		Endif

		For (n=1;n<=numsweeps;n+=1)
			m=0
			For (i=0;i<numpoints;i+=1)

				If (Y_wave[i]==n)
					Y_Wave2[i]=0+m
					m+=1
				Endif
			Endfor
		Endfor

		If (tempVal1==1)
			Display /N=$(SpikeperSweep_graph) /W=(900,50,1400,250 ) /K=1 $(sweepNumberWave) vs $(latencyWave)
			ModifyGraph zColor={Y_wave2,*,*,cindexRGB,0,colorWave}
		Else
			AppendtoGraph /W=$(SpikeperSweep_graph) $(sweepNumberWave) vs $(latencyWave)
			ModifyGraph zColor($sweepNumberWave)={Y_wave2,*,*,cindexRGB,0,colorWave}


		Endif
		ModifyGraph mode=3,marker=19,msize=5,useMrkStrokeRGB=1
		SetAxis/A/N=1/E=1 bottom


	Endif
End



//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
// Function: find_ALR_amplitude
// Calculate amplitude ratio, latency difference, and amplitude/latency ratio for sequential spikes.
Function find_ALR_amplitude(CtrlName)
	String CtrlName
	SVAR FileNameTruncated
	//NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp

	//Input file names
	String sweepNumberFileName
	String latencyWaveFileName
	String amplitudeWaveFileName
	String outputAMPfileName = FileNameTruncated+"_AMPratio"
	String outputLATfileName = FileNameTruncated+"_LATdiff"
	String outputALRfileName = FileNameTruncated+"_ALR"
	String tempWave1

	Variable firstPeak
	Variable secondPeak
	Variable amplitudeRatio
	Variable latencyDifference
	Variable AmpLatRatio
	Variable spiketime = 0.001
	Variable anlysisType


	Prompt sweepNumberFileName, "Wave with Sweep Numbers", popup WaveList("*_ST_*_swp",";","")
	Prompt latencyWaveFileName, "Wave with Spike Times", popup WaveList("*_ST_*", ";", "")
	Prompt amplitudeWaveFileName, "Wave with Amplitudes", popup WaveList("*_AMP_*", ";", "")
	Prompt anlysisType, "Analyze:", popup "All spikes;First pair of spikes"
	DoPrompt "Select Wave to be Analyzed", sweepNumberFileName, latencyWaveFileName,amplitudeWaveFileName,anlysisType

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		//Make Waves
		Wave sweepNumberWave = $sweepNumberFileName
		Wave latencyTimesWave = $latencyWaveFileName
		Wave amplitudesWave = $amplitudeWaveFileName
		
		Variable sweepnum = WaveMax(sweepNumberWave)

		Variable tempX1val
		Variable tempX2val
		Variable ALRindex = 0
		Variable i = 0
		variable totalPoints = numpnts(sweepNumberWave)
		
				
		Make /O /N=(totalPoints-1) $outputAMPfileName =0
		Wave outputAMP = $outputAMPfileName

		Make /O /N=(totalPoints-1) $outputLATfileName =0
		Wave outputLAT = $outputLATfileName
		
		Make /O /N=(totalPoints-1) $outputALRfileName =0
		Wave outputALR = $outputALRfileName
		
		
		Do
			
			If (anlysisType==2)
			
				If(i == 0 || sweepNumberWave[i] != sweepNumberWave[i-1])

					If (sweepNumberWave[i] == sweepNumberWave[i+1])
						//Actual recorded wave with analog spike information
						//tempWave1 = FileNameTruncated+"_"+num2str(sweepNumberWave[i])
						//Add 0.15 milliseconds since all stimuli start at 150 ms into sweep *fix this in the future
						//tempX1val = 0.15+latencyTimesWave[i]
						//						FindPeak /Q /N /R=(tempX1val,(tempX1val+spiketime)) $tempWave1
						//						firstPeak = V_PeakVal
						//						tempX2val = 0.15+latencyTimesWave[i+1]
						//						FindPeak /Q /N /R=(tempX2val,(tempX2val+spiketime)) $tempWave1
						//						secondPeak = V_PeakVal
				
						firstPeak = amplitudesWave[i]
						secondPeak = amplitudesWave[i+1]
				
						amplitudeRatio = abs(secondPeak)/abs(firstPeak)
						latencyDifference = latencyTimesWave[i+1] - latencyTimesWave[i]
						AmpLatRatio = amplitudeRatio/latencyDifference
				
						outputAMP[ALRindex] = amplitudeRatio
						outputLAT[ALRindex] = latencyDifference
						outputALR[ALRindex] = AmpLatRatio
						ALRindex += 1

					Endif
			
				Endif
			
			Else
				If (sweepNumberWave[i] == sweepNumberWave[i+1])
					//					//Actual recorded wave with analog spike information
					//					tempWave1 = FileNameTruncated+"_"+num2str(sweepNumberWave[i])
					//					//Add 0.15 milliseconds since all stimuli start at 150 ms into sweep *fix this in the future
					//					tempX1val = 0.15+latencyTimesWave[i]
					//					FindPeak /Q /N /R=(tempX1val,(tempX1val+spiketime)) $tempWave1
					//					firstPeak = V_PeakVal
					//					tempX2val = 0.15+latencyTimesWave[i+1]
					//					FindPeak /Q /N /R=(tempX2val,(tempX2val+spiketime)) $tempWave1
					//					secondPeak = V_PeakVal
				
					firstPeak = amplitudesWave[i]
					secondPeak = amplitudesWave[i+1]
									
					amplitudeRatio = abs(secondPeak)/abs(firstPeak)
					latencyDifference = latencyTimesWave[i+1] - latencyTimesWave[i]
					AmpLatRatio = amplitudeRatio/latencyDifference
										
					outputAMP[ALRindex] = amplitudeRatio
					outputLAT[ALRindex] = latencyDifference
					outputALR[ALRindex] = AmpLatRatio
					ALRindex += 1

				Endif
			Endif			
			
			i+=1
		While (i <( totalPoints - 1))

		//Delete zeros
		Variable n=totalPoints-2
		Do
			If ((n>=0)&&(outputAMP[n]==0))
				DeletePoints n, 1, outputAMP
				DeletePoints n, 1, outputLAT
				DeletePoints n, 1, outputALR				
			Endif
			n=n-1
		While (n>=0)
				
		Display /W=(900,50,1400,350 ) /K=1 $(outputAMPfileName) vs $(outputLATfileName)
		ModifyGraph mode=3,marker=19,msize=5,useMrkStrokeRGB=1
		ModifyGraph rgb=(43690,43690,43690)
		SetAxis/A/N=2/E=0 bottom
		SetAxis/A/N=1/E=1 left
		Label left "Amplitude ratio (2nd spike amp/1st spike amp)";DelayUpdate
		Label bottom "Interspike Interval (ms)"
		SetDrawEnv xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
		DrawLine 0,1,1,1
		//CurveFit/M=2/W=0 line, $(outputAMPfileName)/X=$(outputLATfileName) /D

	Endif 
End
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///

// Function: findSpikesInSweeps
// Count detected spikes per sweep from a spike-time sweep-index wave.
Function findSpikesInSweeps(ctrlName)
	String ctrlName
	SVAR /Z input_type = root:A:input_type		
	NVAR /Z sweepStartnum = root:A:sweepStartnum
	NVAR /Z sweepEndnum = root:A:sweepEndnum
	SVAR /Z FileNameTruncated

	If ((SVAR_exists(input_type)==0)||(NVAR_exists(sweepStartnum)==0)||(NVAR_exists(sweepEndnum)==0)||(SVAR_exists(FileNameTruncated)==0))
		Abort "Required globals are missing. Load data before counting spikes per sweep."
	Endif
	
	//Input file names
	String sweepNumberWave
	String fileName = FileNameTruncated + input_type+ "_spk_per_swp"
	Variable sweepnum = sweepEndnum-sweepStartnum+1
	
	Prompt sweepNumberWave, "Wave with Sweep Numbers", popup WaveList("*_ST_*_swp",";","")
	Prompt fileName, "Output spikes per sweep file name"
	DoPrompt "Select Wave to be analyzed", sweepNumberWave, fileName
	
	If(V_flag==0) //if cancel clicked on DoPrompt, then skip rest of proc
		Wave WsweepNum = $sweepNumberWave
		Make /O /N=(sweepnum) $fileName = 0
		Wave spikesPerSweep = $fileName
		SetScale /P x, sweepStartnum, 1, "", spikesPerSweep
		
		Variable totalPoints = numpnts(WsweepNum)
		Variable index
		Variable sweepIndex
		Variable sweepOffset = sweepStartnum
		If ((totalPoints>0)&&(WaveMin(WsweepNum)==(sweepStartnum-1)))
			// Find_Peaks stores sweep indices as zero-based 2D-wave columns.
			sweepOffset = sweepStartnum-1
		Endif
		For (index=0; index<totalPoints; index+=1)
			sweepIndex = round(WsweepNum[index]-sweepOffset)
			If ((sweepIndex>=0)&&(sweepIndex<sweepnum))
				spikesPerSweep[sweepIndex] += 1
			Endif
		Endfor
		
		Edit /W=(100,50,150,500) /K=1 /N=SpikesperSweep $(fileName), as "Number of spikes per sweep for "+sweepNumberWave

		Wavestats /Q spikesPerSweep
		Variable spike_avg = V_avg
		Variable spike_sem = V_sem
		String valAsStr
		sprintf valAsStr, "%.3g", spike_sem
		spike_sem = str2num(valAsStr)

		String nb0 = "Statistics"
		String nb_list=WinList(nb0,";","WIN:16")
		If (cmpstr(nb_list,"")==0)
			Print "Average #spikes per sweep = "+num2str(spike_avg)+" ± "+num2str(spike_sem)+" SEM"
		Else
			Notebook $nb0 text= "Average #spikes per sweep = "+num2str(spike_avg)+" ± "+num2str(spike_sem)+" SEM\r"
		Endif
	Endif
End

// Function: intensity_analysis
// Convenience wrapper for the intensity-analysis sequence: detect peaks, count spikes per sweep, and calculate latency differences.
Function intensity_analysis(ctrlName): ButtonControl

	String ctrlName

	Find_Peaks(ctrlName)

	findSpikesInSweeps(ctrlName)

	findLatDiff(ctrlName)


End

//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//Function to speed adaptation analysis steps
// Function: adaptation_analysis
// Convenience wrapper for adaptation experiments: zero sweeps and run the adaptation Find_Peaks path.
Function adaptation_analysis(ctrlName): ButtonControl
	String ctrlName
	Zerosweeps("ctrlName",2)
	Find_Peaks("adaptation")

End

//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//Function to speed adaptation analysis steps
// Function: column_analysis
// Convenience wrapper for column-wave analysis through the Find_Peaks columns path.
Function column_analysis(ctrlName): ButtonControl
	String ctrlName
	//Zerosweeps("columns",2)
	Find_Peaks("columns")

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

