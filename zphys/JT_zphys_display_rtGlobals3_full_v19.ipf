#pragma rtGlobals=3        // Full Igor Pro 9 cleanup version.


// =================================================================================================
// JT_zphys_display.ipf -- cleaned display/graph utilities for the zPhys panel
//
// Purpose:
//   Graph, table, waterfall, export, cursor, and display-panel helper routines used by JT_Controls.
//
// Notes:
//   - Public function names and control callback names are intentionally preserved.
//   - Wave-name construction conventions are preserved, including FileNameTruncated + "_" + sweep
//     number patterns where the original display code expects them.
//   - This full version uses #pragma rtGlobals=3 for stricter Igor Pro 9 checking.
//   - Threshold-slider drawing is routed through helper functions so panel and graph sliders
//     redraw the red event-detection line consistently.
// =================================================================================================


////////////////////////////////////////////////////////////////////////////////////////////////////
// Internal helpers

Static Function JTz_DisplayWaveExists(waveName)
	String waveName
	WAVE /Z w = $(waveName)
	Return WaveExists(w)
End

Static Function JTz_DrawEventThreshold(graphName, thresholdValue)
	String graphName
	Variable thresholdValue

	If (strlen(graphName) == 0 || numtype(thresholdValue) != 0)
		Return 0
	Endif

	SetDrawLayer /W=$graphName /K UserFront
	SetDrawLayer /W=$graphName UserFront
	SetDrawEnv /W=$graphName xcoord=rel, ycoord=left, linefgc=(65535,0,0), dash=1
	DrawLine /W=$graphName 0, thresholdValue, 1, thresholdValue
	Return 1
End

Static Function JTz_SetDblExpYOffsetZero()
	// The double-exponential histogram fit expects a K0 offset coefficient in the current folder.
	Variable /G K0 = 0
End

Static Function/S JTz_ResolvePanelWavePath()
	// Resolve root:A:tempwave even if the current data folder has changed.
	// The panel stores tempwave as a bare wave name for normal Sutter/HEKA workflows,
	// so arrow-button navigation must reconstruct the data-folder path before appending.
	SVAR /Z tempwave = root:A:tempwave
	If (!SVAR_Exists(tempwave) || strlen(tempwave) == 0)
		Return ""
	Endif

	WAVE /Z directWave = $(tempwave)
	If (WaveExists(directWave))
		Return tempwave
	Endif

	SVAR /Z data_type = root:A:data_type
	SVAR /Z tempfilefolder = root:A:tempfilefolder
	SVAR /Z tempfolder = root:A:tempfolder
	If (SVAR_Exists(data_type) && SVAR_Exists(tempfilefolder) && SVAR_Exists(tempfolder))
		If (strlen(data_type) > 0 && strlen(tempfilefolder) > 0 && strlen(tempfolder) > 0)
			String candidate = "root:" + PossiblyQuoteName(data_type) + ":" + PossiblyQuoteName(tempfilefolder) + ":" + PossiblyQuoteName(tempfolder) + ":" + PossiblyQuoteName(tempwave)
			WAVE /Z folderWave = $(candidate)
			If (WaveExists(folderWave))
				Return candidate
			Endif
		Endif
	Endif

	Return tempwave
End

Static Function JTz_ClearMainPanelGraph()
	String graphName = "JT_Controls#embedwin"
	String graphTraces = TraceNameList(graphName, ";", 1)
	Variable i
	For (i = 0; i < ItemsInList(graphTraces); i += 1)
		String tempTrace = StringFromList(i, graphTraces)
		RemoveFromGraph /Z /W=$graphName $tempTrace
	Endfor
End

Static Function JTz_AppendSweepToMainPanel(sweepNum)
	Variable sweepNum

	SVAR /Z tempwave = root:A:tempwave
	NVAR /Z sweepStartnum = root:A:sweepStartnum
	NVAR /Z sweepEndnum = root:A:sweepEndnum
	NVAR /Z sweepCurrent = root:A:sweepCurrent
	NVAR /Z eventAmp = root:A:eventamp
	NVAR /Z spikeamp = root:A:spikeamp

	If (!SVAR_Exists(tempwave) || !NVAR_Exists(sweepStartnum) || !NVAR_Exists(sweepEndnum) || !NVAR_Exists(sweepCurrent))
		Abort "zPhys display globals are not initialized. Run zPhys Panel first."
	Endif

	String panelWavePath = JTz_ResolvePanelWavePath()
	WAVE /Z panelWave = $(panelWavePath)
	If (!WaveExists(panelWave))
		Abort "Displayed wave not found: " + tempwave
	Endif

	If (sweepNum < sweepStartnum)
		sweepNum = sweepStartnum
	ElseIf (sweepNum > sweepEndnum)
		sweepNum = sweepEndnum
	Endif
	sweepCurrent = sweepNum

	JTz_ClearMainPanelGraph()
	If (DimSize(panelWave, 1) > 0)
		AppendToGraph /W=JT_Controls#embedwin panelWave[][sweepCurrent - 1]
	Else
		AppendToGraph /W=JT_Controls#embedwin panelWave
	Endif

	ModifyGraph /W=JT_Controls#embedwin rgb=(0,0,0)
	If (NVAR_Exists(eventAmp))
		JTz_DrawEventThreshold("JT_Controls#embedwin", eventAmp)
		If (NVAR_Exists(spikeamp))
			Slider slider2, win=JT_Controls, value=eventAmp, limits={spikeamp,0,0}
		Else
			Slider slider2, win=JT_Controls, value=eventAmp
		Endif
	Endif
	SetVariable setvar4, win=JT_Controls, value=sweepCurrent
	ControlUpdate /W=JT_Controls setvar4
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Waves in a Graph


Function Plot_Waves(ctrlName, tempwavenum1, tempwavenum2)
	String ctrlName				// Name or full path of wave to display.
	Variable tempwavenum1, tempwavenum2	// 1-based sweep/column range.

	Variable i
	NVAR /Z eventAmp = root:A:eventamp
	NVAR /Z sweepTime = root:A:sweepTime

	WAVE /Z temp2DWave = $(ctrlName)
	If (!WaveExists(temp2DWave))
		Abort "Plot_Waves could not find wave: " + ctrlName
	Endif

	Variable numCols = DimSize(temp2DWave, 1)
	Variable firstSweep = round(tempwavenum1)
	Variable lastSweep = round(tempwavenum2)

	If (firstSweep < 1)
		firstSweep = 1
	Endif
	If (lastSweep < firstSweep)
		lastSweep = firstSweep
	Endif
	If (numCols > 0)
		If (firstSweep > numCols)
			firstSweep = numCols
		Endif
		If (lastSweep > numCols)
			lastSweep = numCols
		Endif
	Endif

	If (numCols > 0)
		Display /N=Wave_Graph /W=(200,10,1200,610) /K=1 temp2DWave[][firstSweep - 1]
	Else
		Display /N=Wave_Graph /W=(200,10,1200,610) /K=1 temp2DWave
	Endif
	String graphName = S_name		// Special variable created by Display.

	If (numCols > 0 && lastSweep > firstSweep)
		For (i = firstSweep; i < lastSweep; i += 1)
			AppendToGraph /W=$graphName temp2DWave[][i]
		Endfor
	Endif

	ModifyGraph /W=$graphName rgb=(0,0,0)
	Label /W=$graphName left "Current"; DelayUpdate
	Label /W=$graphName bottom "Time"
	Variable sweepTimeVal = 0
	If (NVAR_Exists(sweepTime))
		sweepTimeVal = sweepTime
	Endif
	If (sweepTimeVal == 1)
		SetAxis /W=$graphName /A/N=1/E=1 bottom
	Else
		SetAxis /W=$graphName /A/N=0/E=0 bottom
	Endif
	SetAxis /W=$graphName /A/N=2/E=0 left

	If (NVAR_Exists(eventAmp))
		JTz_DrawEventThreshold(graphName, eventAmp)
	Endif

	String graphTraces = TraceNameList(graphName, ";", 1)
	String tempTrace = StringFromList(0, graphTraces)
	If (strlen(tempTrace) > 0)
		Variable leftX = DimOffset(temp2DWave, 0)
		Variable rightX = DimOffset(temp2DWave, 0) + (DimSize(temp2DWave, 0) - 1) * DimDelta(temp2DWave, 0)
		Cursor /W=$graphName A, $tempTrace, leftX
		Cursor /W=$graphName B, $tempTrace, rightX
		ShowInfo /W=$graphName
	Endif

	Return 1
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Field Potential wave in a Graph


Function Display_Waves_Startle(ctrlName) : ButtonControl
	String ctrlName

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	NVAR sweepCurrent = root:A:sweepCurrent

	String tempfolder1 = GetDataFolder(0)
	If (cmpstr(tempfolder1, tempfolder) != 0)
		Abort "Startle analysis must be run from the currently loaded series folder."
	Endif

	// Use the current sweep by default. The original code left these uninitialized, which could
	// request column -1 under rtGlobals=3.
	Variable tempwavenum1 = sweepCurrent
	Variable tempwavenum2 = sweepCurrent
	Plot_Waves(tempwave, tempwavenum1, tempwavenum2)

	String topGraph = WinName(0, 1)
	Graph_Panel(topGraph)
	SetAxis /W=$topGraph bottom 0.4, 0.8

	String graphTraces = TraceNameList(topGraph, ";", 1)
	String tempTrace = StringFromList(0, graphTraces)
	If (strlen(tempTrace) == 0)
		Abort "No trace found in startle graph."
	Endif

	Cursor /W=$topGraph /H=2 A, $tempTrace, 0.4
	Cursor /W=$topGraph /H=2 B, $tempTrace, 0.8

	Variable leftval = pcsr(A)
	Variable rightval = pcsr(B)

	// Preserve the original p-p field-potential measurement window.
	WaveStats /Q /R=[leftval,rightval] $tempwave
	Variable FP_amp1 = V_Max - V_Min

	TextBox /W=$topGraph /C/N=text0/F=0/A=MC "Field potential peak-to-peak amplitude is " + num2str(1000 * FP_amp1) + " mV at approx time: " + num2str(V_maxRowLoc) + " sec."
	Print "Field potential peak-to-peak amplitude is " + num2str(1000 * FP_amp1) + " mV at approx time: " + num2str(V_maxRowLoc) + " sec."

	SetAxis /W=$topGraph bottom 0.49, 0.65

	Variable tempFPstart = NaN
	If (V_maxRowLoc < V_minRowLoc)
		tempFPstart = V_maxRowLoc - ((V_minRowLoc - V_maxRowLoc) / 2)
	ElseIf (V_minRowLoc < V_maxRowLoc)
		tempFPstart = V_minRowLoc - ((V_maxRowLoc - V_minRowLoc) / 2)
	Endif

	If (numtype(tempFPstart) == 0)
		Cursor /W=$topGraph A, $tempTrace, tempFPstart
		Print "FP event starts at time " + num2str(tempFPstart)
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Waves in a Graph


Function Display_Waves(ctrlName) : ButtonControl
	String ctrlName

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	String tempfolder1 = GetDataFolder(0)
	Variable tempwavenum1 = sweepCurrent
	Variable tempwavenum2 = sweepCurrent
	Variable didPlot = 0

	If (cmpstr(tempfolder1, "root") == 0)
		Plot_Waves(tempwave, 1, 1)
		didPlot = 1
	ElseIf (cmpstr(tempfolder1, tempfolder) == 0)
		ControlInfo /W=JT_Controls check201		// Multiple waves checkbox.
		Variable checknum201 = V_Value
		If (checknum201 == 1)
			tempwavenum1 = sweepStartnum
			tempwavenum2 = sweepEndnum
			Prompt tempwavenum1, "First wave:"
			Prompt tempwavenum2, "Last wave:"
			DoPrompt "Plot multiple waves", tempwavenum1, tempwavenum2
			If (V_flag == 0)
				Plot_Waves(tempwave, tempwavenum1, tempwavenum2)
				didPlot = 1
			Endif
		Else
			Plot_Waves(tempwave, tempwavenum1, tempwavenum2)
			didPlot = 1
		Endif
	Else
		Abort "Current data folder is not root or the loaded series folder."
	Endif

	If (didPlot)
		String topGraph = WinName(0, 1)
		Graph_Panel(topGraph)
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Stimulus Wave in a Graph


Function Display_StimWave(ctrlName) : ButtonControl
	String ctrlName

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR stim_type = root:A:stim_type
	SVAR RootFolder_list = root:Packages:MPVars:RootFolder_list

	String currentDF = GetDataFolder(1)
	Variable tempvar = 1		// 1=yes current sweep/folder, 2=no select another folder.
	Variable tempvar1 = 0	// 1=append to top graph, 2=new graph, 0=no top graph.

	String topGraph = WinName(0, 1)
	If (cmpstr(topGraph, "") != 0)
		Prompt tempvar, "For current sweep?", popup "yes;no"
		Prompt tempvar1, "Append to Top Graph?", popup "yes;no"
		DoPrompt "Append Stimulus Trace", tempvar, tempvar1
	Else
		Prompt tempvar, "For current sweep?", popup "yes;no"
		DoPrompt "Display Stimulus File", tempvar
	Endif
	If (V_flag != 0)
		SetDataFolder currentDF
		Return -1
	Endif

	If (tempvar == 2)
		String tempfolder1
		Prompt tempfolder1, "Data Folder", popup (RootFolder_list)
		DoPrompt "Select Data File", tempfolder1
		If (V_flag != 0)
			SetDataFolder currentDF
			Return -1
		Endif

		String Folderlist = tempfolder1 + "_list"
		SVAR Serieslist = root:Packages:MPVars:$(FolderList)
		String tempfolder2
		Prompt tempfolder2, "Folder", popup (Serieslist)
		DoPrompt "Select Stimulus from Series", tempfolder2
		If (V_flag != 0)
			SetDataFolder currentDF
			Return -1
		Endif
		SetDataFolder root:$(tempfolder1):$(tempfolder2)
	Endif

	SVAR /Z FileNameTruncated
	If (!SVAR_Exists(FileNameTruncated))
		SetDataFolder currentDF
		Abort "No FileNameTruncated string was found in the selected data folder."
	Endif

	String stimwave = FileNameTruncated + stim_type
	WAVE /Z wStim = $(stimwave)
	If (!WaveExists(wStim))
		SetDataFolder currentDF
		Abort "No stimulus wave found: " + stimwave
	Endif

	If (tempvar1 == 1)
		String traces = TraceNameList(topGraph, ";", 1)
		String traceMatch = ListMatch(traces, stimwave)
		If (cmpstr(traceMatch, "") == 0)
			If (DimSize(wStim, 1) > 0)
				AppendToGraph /W=$topGraph /R=right wStim[][0]
			Else
				AppendToGraph /W=$topGraph /R=right wStim
			Endif
		Else
			SetDataFolder currentDF
			Abort "Stimulus wave is already in " + topGraph
		Endif
	Else
		If (DimSize(wStim, 1) > 0)
			Display /N=Stim_graph /W=(1000,0,1400,100) /K=1 wStim[][0]
		Else
			Display /N=Stim_graph /W=(1000,0,1400,100) /K=1 wStim
		Endif
		ModifyGraph rgb=(0,0,0)
		SetAxis /A/N=0/E=1 bottom
		SetAxis /A/N=2/E=2 left
		Label left "Voltage"
		Label bottom "Time"
		CheckBox checktemp1 pos={0,0}, title="Axes", mode=0, value=0, proc=Noaxes
	Endif

	DoWindow /F JT_Controls
	SetDataFolder currentDF
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
Function UserCursorAdjust(graphName)  //Found on WaveMetrics Exchange
	String graphName

	DoWindow/F $graphName			// Bring graph to front
	if (V_Flag == 0)					// Verify that graph exists
		return -1
	endif

	NewDataFolder/O root:tmp_PauseforCursorDF
	Variable /G root:tmp_PauseforCursorDF:canceled
	String /G root:tmp_PauseforCursorDF:graph
	SVAR graph=root:tmp_PauseforCursorDF:graph
	graph=graphName
	NVAR canceled= root:tmp_PauseforCursorDF:canceled
	Variable returncanceled

	NewPanel/EXT=0 /N=tmp_PauseforCursor /Host=$graphname /W=(0,0,110,80) as "Paused!"

	DrawText /W=# 10,20,"Adjust cursors..."
	Button button0,win=#, pos={10,30},size={92,20}, fColor=(65535,0,0 ), proc=UserCursorAdjust_ContButtonProc, title="Continue"
	Button button1,win=#, pos={10,50},size={92,20}, proc=UserCursorAdjust_CancelBProc,title="Cancel"

	PauseForUser $graphName#tmp_PauseforCursor, $graphName

	returncanceled = canceled			// Copy from global to local before global is killed
	KillDataFolder root:tmp_PauseforCursorDF

	//will return -1 for no graph, 0 for completed, and 1 for cancelled
	return returncanceled
End

Function UserCursorAdjust_ContButtonProc(ctrlName) : ButtonControl
	String ctrlName
	NVAR canceled= root:tmp_PauseforCursorDF:canceled
	SVAR graph= root:tmp_PauseforCursorDF:graph

	canceled=0
	KillWindow $graph#tmp_PauseforCursor			// Kill self
End

Function UserCursorAdjust_CancelBProc(ctrlName) : ButtonControl
	String ctrlName
	NVAR canceled= root:tmp_PauseforCursorDF:canceled
	SVAR graph= root:tmp_PauseforCursorDF:graph

	canceled=1
	KillWindow $graph#tmp_PauseforCursor			// Kill self
End



////////////////////////////////////////////////////////////////////////////////////////////////////
//Tile graphs


Function Tile_graphs(ctrlName) : ButtonControl
	String ctrlName
	String cmd

	String graphs = WinList("*", ";", "WIN:1")
	Variable graphnum = ItemsInList(graphs)
	If (graphnum <= 0)
		Abort "No graphs are open to tile."
	Endif

	String info = IgorInfo(0)
	String screen1RectStr = StringByKey("SCREEN1", info)
	Variable depth, left, top, right, bottom
	sscanf screen1RectStr, "DEPTH=%d,RECT=%d,%d,%d,%d", depth, left, top, right, bottom

	Variable bitnum = 1	// Graph windows only.
	Variable tempnum1
	Variable rownum = ceil(graphnum / 2)
	If (rownum < 1)
		rownum = 1
	Endif
	Variable columnnum = ceil(graphnum / rownum)
	If (columnnum < 1)
		columnnum = 1
	Endif
	Variable percentwide = 90
	Variable percenthigh = 90

	Prompt tempnum1, "Auto?", popup "Yes;No"
	DoPrompt "Define Graph array", tempnum1
	If (V_flag != 0)
		Return -1
	Endif

	If (tempnum1 == 1)
		sprintf cmd, "TileWindows/O=%d/W=(%d,%d,%d,%d)", bitnum, 0.1 * right, 0.01 * bottom, 0.8 * right, 0.8 * bottom
		Execute cmd
	Else
		Prompt rownum, "Rows:"
		Prompt columnnum, "Columns:"
		Prompt percentwide, "%width"
		Prompt percenthigh, "%height"
		DoPrompt "Define Graph array", rownum, columnnum, percentwide, percenthigh
		If (V_flag != 0)
			Return -1
		Endif
		If (rownum < 1 || columnnum < 1)
			Abort "Rows and columns must be at least 1."
		Endif
		If (percentwide <= 0 || percenthigh <= 0)
			Abort "Width and height must be > 0%."
		Endif
		percentwide /= 100
		percenthigh /= 100
		sprintf cmd, "TileWindows/O=%d/A=(%d,%d)/W=(%d,%d,%d,%d)", bitnum, rownum, columnnum, 0, 0, percentwide * right, percenthigh * bottom
		Execute cmd
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Add Waves or Columns in a table or 2D wave to a new table or 2D wave


Function Table_Waves(ctrlName) : ButtonControl
	String ctrlName
	Variable tempwavenum1
	Variable tempwavenum2
	Variable i, numcols
	String tablewaves
	String tempname1 = "PPS"

	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum

	WAVE /Z temp2Dwave = $(tempwave)
	Variable waveDelta = NaN
	If (WaveExists(temp2Dwave))
		waveDelta = DimDelta(temp2Dwave, 0)
	Endif

	If (cmpstr(data_type, "") == 0)
		tablewaves = ""
		tempwavenum1 = sweepStartnum
		tempwavenum2 = sweepEndnum
		Prompt tempwavenum1, "First wave:"
		Prompt tempwavenum2, "Last wave:"
		DoPrompt "Add waves to table", tempwavenum1, tempwavenum2
		If (V_flag != 0)
			Return -1
		Endif
		SVAR FileNameTruncated

		DoWindow /K WAVE_table
		Edit /K=1 /N=WAVE_table as "Table of " + FileNameTruncated + " waves from " + num2str(tempwavenum1) + " to " + num2str(tempwavenum2)
		For (i = tempwavenum1; i <= tempwavenum2; i += 1)
			tablewaves = FileNameTruncated + "_" + num2str(i) + input_type
			If (WaveExists($tablewaves))
				AppendToTable $tablewaves
			Else
				Print "Skipped missing wave: " + tablewaves
			Endif
		Endfor

	ElseIf (cmpstr(data_type, "SutterPatch") == 0 || cmpstr(data_type, "SUTTER") == 0)
		If (!WaveExists(temp2Dwave))
			Abort "2D source wave not found: " + tempwave
		Endif

		tempwavenum1 = sweepStartnum
		tempwavenum2 = sweepEndnum
		Prompt tempname1, "Name of columns wave:"
		Prompt tempwavenum1, "First wave:"
		Prompt tempwavenum2, "Last wave:"
		DoPrompt "Add single columns (waves) to 2D wave", tempname1, tempwavenum1, tempwavenum2
		If (V_flag != 0)
			Return -1
		Endif

		For (i = tempwavenum1; i <= tempwavenum2; i += 1)
			String newcolwave = "root:A:Avg:" + tempname1 + "_column" + num2str(i)
			WAVE /Z col2Dwave = $(newcolwave)

			If (!WaveExists(col2Dwave))
				MatrixOP $newcolwave = col(temp2Dwave, i - 1)
				SetScale /P x 0, waveDelta, "s", $newcolwave
			Else
				numcols = DimSize(col2Dwave, 1)
				If (numcols == 0)
					numcols = 1
				Endif
				Redimension /N=(-1, numcols + 1) col2Dwave
				MatrixOP /FREE tempfreewave = col(temp2Dwave, i - 1)
				col2Dwave[][numcols] = tempfreewave[p]
			Endif
		Endfor
	Else
		Abort "Wave data type not recognized for Table_Waves: " + data_type
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Add Waves to a Waterfall Plot



Function Waterfall_waves(ctrlName) : ButtonControl
	String ctrlName
	Variable tempwavenum1
	Variable tempwavenum2
	Variable i, tempstim

	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	SVAR FileNameTruncated

	tempwavenum1 = sweepStartnum
	tempwavenum2 = sweepEndnum
	tempstim = 2	// Default: do not add stimulus wave.

	String stimwave = FileNameTruncated + stim_type
	Variable hasStim = WaveExists($stimwave)
	Prompt tempwavenum1, "First wave:"
	Prompt tempwavenum2, "Last wave:"
	If (hasStim)
		Prompt tempstim, "Add stim wave?", popup "Yes;No"
		DoPrompt "Create waterfall plot", tempwavenum1, tempwavenum2, tempstim
	Else
		DoPrompt "Create waterfall plot", tempwavenum1, tempwavenum2
	Endif
	If (V_flag != 0)
		Return -1
	Endif

	If (tempwavenum2 < tempwavenum1)
		Abort "Last wave must be >= first wave."
	Endif

	String waterfallname = FileNameTruncated + "_M" + num2str(tempwavenum1) + "to" + num2str(tempwavenum2)
	Variable col = 0
	Variable outCols = tempwavenum2 - tempwavenum1 + 1
	If (hasStim && tempstim == 1)
		outCols += 1
	Endif

	If (cmpstr(data_type, "") == 0)
		String firstWaveName = FileNameTruncated + "_" + num2str(tempwavenum1) + input_type
		WAVE /Z firstWave = $firstWaveName
		If (!WaveExists(firstWave))
			Abort "First waterfall source wave not found: " + firstWaveName
		Endif

		Make /O /N=(DimSize(firstWave, 0), outCols) $waterfallname = NaN
		WAVE mOutLegacy = $waterfallname
		SetScale /P x DimOffset(firstWave, 0), DimDelta(firstWave, 0), WaveUnits(firstWave, 0), mOutLegacy

		If (hasStim && tempstim == 1)
			WAVE /Z wStimTemp = $stimwave
			If (WaveExists(wStimTemp))
				mOutLegacy[][col] = wStimTemp[p] * 1e-10
				col += 1
			Endif
		Endif

		For (i = tempwavenum1; i <= tempwavenum2; i += 1)
			String tempwave2 = FileNameTruncated + "_" + num2str(i) + input_type
			WAVE /Z wavetemp = $tempwave2
			If (WaveExists(wavetemp))
				mOutLegacy[][col] = wavetemp[p]
				col += 1
			Else
				Print "Skipped missing waterfall wave: " + tempwave2
			Endif
		Endfor
	Else
		WAVE /Z temp2DWave = $(tempwave)
		If (!WaveExists(temp2DWave))
			Abort "Waterfall source 2D wave not found: " + tempwave
		Endif

		Variable maxCols = DimSize(temp2DWave, 1)
		If (maxCols <= 0)
			Duplicate /O temp2DWave, $waterfallname
		Else
			If (tempwavenum1 < 1)
				tempwavenum1 = 1
			Endif
			If (tempwavenum2 > maxCols)
				tempwavenum2 = maxCols
			Endif
			outCols = tempwavenum2 - tempwavenum1 + 1
			If (hasStim && tempstim == 1)
				outCols += 1
			Endif

			Make /O /N=(DimSize(temp2DWave, 0), outCols) $waterfallname = NaN
			WAVE mOut2D = $waterfallname
			SetScale /P x DimOffset(temp2DWave, 0), DimDelta(temp2DWave, 0), WaveUnits(temp2DWave, 0), mOut2D

			If (hasStim && tempstim == 1)
				WAVE /Z temp2DStimWave = $(stimwave)
				If (WaveExists(temp2DStimWave))
					If (DimSize(temp2DStimWave, 1) > 0)
						MatrixOP /FREE wStimCol = col(temp2DStimWave, 0)
						mOut2D[][col] = wStimCol[p] * 1e-10
					Else
						mOut2D[][col] = temp2DStimWave[p] * 1e-10
					Endif
					col += 1
				Endif
			Endif

			For (i = tempwavenum1; i <= tempwavenum2; i += 1)
				MatrixOP /FREE wTempCol = col(temp2DWave, i - 1)
				mOut2D[][col] = wTempCol[p]
				col += 1
			Endfor
		Endif
	Endif

	WAVE mOutFinal = $waterfallname
	If (DimSize(mOutFinal, 1) == 0)
		Abort "No waves were added to the waterfall plot."
	Endif

	NewWaterfall /K=1 /N=Waterfall_graph /W=(0,0,1000,500) mOutFinal
	ModifyWaterfall angle=80, axlen=0.9, hidden=0
	ModifyGraph rgb=(0,0,0)
	ModifyGraph lblRot(right)=180
	ModifyGraph tick(left)=3, noLabel(left)=2, axThick(left)=0, margin(left)=0
	Label right "Sweep #"
	Label bottom "Time"

	String topGraph = WinName(0, 1)
	Graph_Panel(topGraph)
End


////////////////////////////////////////////////////////////////////////////////////////////////////
//Save Graph(s) as a picture

Function Save_Pict (ctrlName): ButtonControl
	string ctrlName
	string cmd

	variable resolution=300
	variable width=400
	variable height=200
	variable linesize=1
	variable format
	variable j
	variable temp1=0

	//List all graphs
	String graphs=WinList("*",";","WIN:1") // A list of all graphs
	String topGraph = WinName(0, 1)	// Name of top graph

	If (itemsinlist(graphs)>0)

		If (itemsinlist(graphs)>1&&cmpstr(ctrlName,"ppict")!=0)
			Prompt temp1, "Select", popup "Top Graph;All Graphs"
			DoPrompt "Which graph(s) to save?", temp1
			If (V_flag==1)	//if cancel clicked on DoPrompt, then skip rest of proc
				Abort "User canceled"
			Endif
		Endif
		Prompt format, "Picture format", popup "png;jpg;tiff;eps"
		Prompt resolution, "resolution DPI"
		Prompt width, "width (pixels)"
		Prompt height, "height (pixels)"
		Prompt linesize, "line thickness (points)"

		If (temp1<2)
			graphs=topGraph
			DoPrompt "Export "+topGraph+" as Picture", format,resolution, width, height,linesize
		Elseif(temp1==2)
			DoPrompt "Export graphs as pictures", format,resolution, width, height,linesize
		Endif
		If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

			//variable width = width_cm*28.35 //28.35 points per cm or 72 points per inch
			//variable height = height_cm*28.35


			For(j=0;j<itemsinlist(graphs);j+=1)
				string graph=stringfromlist(j,graphs)
				String graphtraces=TraceNameList(graph,";",1)
				String temptrace=stringfromlist(0,graphtraces)
				If (strlen(temptrace) == 0)
					Print "Skipped graph with no traces: " + graph
					Continue
				Endif

				wave wave1 = WaveRefIndexed(graph,0,3)
				string graphwavename= NameOfWave(wave1)  // "" for top graph or table
				string pictname = "Graph_"+graphwavename

				ModifyGraph /W=$graph lsize=linesize  //make lines thinner for resolution

				If (format==1)
					Sprintf cmd, "SavePICT /O /TRAN=1 /WIN=%s /P=Desktop/E=-5/RES=%d /W=(0,0,%d,%d) as \"%s.png\"", graph,resolution, width, height, pictname
					Execute cmd
					Print pictname+" saved to Desktop at as PNG ("+num2str(resolution)+" dpi)"
				Elseif(format==2)
					Sprintf cmd, "SavePICT /O /WIN=%s /P=Desktop/E=-6 /Q=1 /RES=%d /W=(0,0,%d,%d) as \"%s.jpg\"", graph,resolution, width, height, pictname
					Execute cmd
					Print pictname+" saved to Desktop at as JPG ("+num2str(resolution)+" dpi)"
				ElseIf (format==3)
					Sprintf cmd, "SavePICT /O /WIN=%s /P=Desktop/E=-7/RES=%d /W=(0,0,%d,%d) as \"%s.tif\"", graph,resolution, width, height, pictname
					Execute cmd
					Print pictname+" saved to Desktop at as TIFF ("+num2str(resolution)+" dpi)"
				ElseIf (format==4)
					Sprintf cmd, "SavePICT /O /WIN=%s /P=Desktop/E=-3/RES=%d /W=(0,0,%d,%d) as \"%s.eps\"", graph,resolution, width, height, pictname
					Execute cmd
					Print pictname+" saved to Desktop at as EPS ("+num2str(resolution)+" dpi)"
				Endif
				Print num2str(height)+"pixels X "+num2str(width)+"pixels ("+num2str(linesize)+"  point line )"
			Endfor
		Endif
	Else
		Abort "No Graph to save"
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Save Graph as a Igor Binary for JT_Controls

Function Save_Binary (ctrlName): ButtonControl
	String ctrlName
	String waveListToSave = ""
	string savename
	String wavename1
	Variable i

	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	SVAR FileNameTruncated

	String currentDF = GetDataFolder(1)

	String topGraph = WinName(0, 1)	// Name of top graph
	DoWindow $topGraph
	If (V_flag==1)
		String Traces=TraceNameList(topGraph,";",1)

		If  (ItemsinList(Traces)>1)
			//get full path and name of wave
			wave wave1 = WaveRefIndexed("",0,3)
			string wave1folder = GetWavesDataFolder (wave1,1)
			SetDataFolder wave1folder
			Variable tempwavenum1 = sweepStartnum
			variable tempwavenum2 = sweepEndnum
			Prompt tempwavenum1, "First wave:"
			Prompt tempwavenum2, "Last wave:"
			DoPrompt "Accumulate Waves", tempwavenum1, tempwavenum2
			If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
				String saveTablename = FileNameTruncated+"_"+num2str(tempwavenum1)+"to"+num2str(tempwavenum2)
				Edit /N=$saveTablename /K=1 $(FileNameTruncated+"_"+num2str(tempwavenum1)+input_type)
				For (i=tempwavenum1; i< tempwavenum2; i+=1)
					AppendtoTable /W=$saveTablename $(FileNameTruncated+"_"+num2str(i+1)+input_type)
				Endfor
				savename = saveTablename+".pxp"
				SaveTableCopy /O/P=Desktop /T=0 /W=$saveTablename as savename
				print "Waves " +saveTablename+" saved."
				DoWindow /K $saveTablename
			Endif
		Else
			//get full path and name of wave
			wave wave1 = WaveRefIndexed("",0,3)
			wavename1 = GetWavesDataFolder (wave1,1)+NameOfWave(wave1)
			savename= NameOfWave(wave1)+".ibw"  // "" for top graph or table
			Save/C /O/P=Desktop $wavename1 as savename
			print "Wave " +NameOfWave(wave1)+" saved."
		Endif
		SetDataFolder currentDF
	Else
		Abort "No Graph to save"
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Analysis Waves in a Graph

Function Display_Wanalysis (ctrlName): ButtonControl
	string ctrlName
	string cmd
	string inputname
	string inputwave
	string tempfolder1
	variable checknum
	NVAR eventAmp = root:A:eventAmp
	String currentDF = "root:A:"
	String ListofFolderNames=""
	String Foldername
	Variable index=0
	do
		Foldername = GetIndexedObjName(currentDF,4, index)
		if (strlen(Foldername) == 0)
			break
		endif
		ListofFolderNames+=Foldername+";"
		index+=1
	while(1)

	Prompt tempfolder1, "Folder", popup (ListofFolderNames)
	DoPrompt "Select an Analysis Folder", tempfolder1

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		currentDF = "root:A:"+tempfolder1+":"
		String ListofwaveNames=""
		String tempwavename
		index=0
		do
			tempwavename = GetIndexedObjName(currentDF,1, index)
			if (strlen(tempwavename) == 0)
				break
			endif
			ListofwaveNames+=tempwavename+";"
			index+=1
		while(1)

		Prompt inputname, "Wave", popup (ListofwaveNames)
		DoPrompt "Select an Analysis Wave", inputname
		If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

			inputwave = currentDF+inputname

			Display /N=Analysis_graph /W=(200,0,1000,600) /K=1 $inputwave
			ModifyGraph rgb=(0,0,0)

			SetAxis/A/N=0/E=0 bottom
			SetAxis/A/N=2/E=2 left
			Cursor A,  $inputname,  leftx($inputwave)
			Cursor B, $inputname, numpnts($inputwave)-1
			Showinfo

			If (cmpstr(tempfolder1,"Concat")==0)
				string topGraph = WinName (0, 1)		// get name of the target graph
				Graph_Panel(topGraph) //Display Graph Panel
				Button pfindpeaks, disable = 0
				Slider slider1, disable = 0, limits={eventAmp,0,0}

			Endif

		Endif
	Endif

End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Histograms in a Graph


Function Display_HistWaves(ctrlName) : ButtonControl
	String ctrlName
	String inputwave

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	String savedDF = GetDataFolder(1)

	SetDataFolder root:A:Concat:
	String histList = WaveList("*_H*", ";", "")
	If (ItemsInList(histList) == 0)
		SetDataFolder savedDF
		Abort "No histogram waves were found in root:A:Concat:."
	Endif

	Prompt inputwave, "Hist Wave", popup histList
	DoPrompt "Select Hist wave", inputwave
	If (V_flag != 0)
		SetDataFolder savedDF
		Return -1
	Endif

	String inputname = NameOfWave($inputwave)
	Display /N=hist_graph /W=(1000,600,1600,900) /K=1 $inputwave
	ModifyGraph useBarStrokeRGB=1, hbFill=4, useNegPat=1, barStrokeRGB=(0,0,0), mode=5, rgb=(32768,32770,65535)
	Cursor /P A, $inputname, DimOffset($inputwave, 0)
	Cursor /P B, $inputname, DimSize($inputwave, 0)

	ShowInfo
	SetAxis /A/N=0/E=1 bottom
	Label left "Number of Events"
	Label bottom "Time (s)"

	JTz_SetDblExpYOffsetZero()
	CurveFit/NTHR=0/TBOX=768 /H="1000" dblexp_XOffset $inputwave [pcsr(A),pcsr(B)] /D
	SetDataFolder savedDF
End


////////////////////////////////////////////////////////////////////////////////////////////////////
//Display sweepCurrent Wave in Panel


Function Display_CurrentWave(ctrlName, varNum, varStr, varName) : SetVariableControl
	String ctrlName
	Variable varNum
	String varStr
	String varName

	JTz_AppendSweepToMainPanel(varNum)
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Next Wave in Panel


Function Display_NextWave(ctrlName) : ButtonControl
	String ctrlName
	NVAR sweepCurrent = root:A:sweepCurrent
	NVAR sweepEndnum = root:A:sweepEndnum

	If (sweepCurrent < sweepEndnum)
		JTz_AppendSweepToMainPanel(sweepCurrent + 1)
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
//Display Previous Wave in Panel


Function Display_PrevWave(ctrlName) : ButtonControl
	String ctrlName
	NVAR sweepCurrent = root:A:sweepCurrent
	NVAR sweepStartnum = root:A:sweepStartnum

	If (sweepCurrent > sweepStartnum)
		JTz_AppendSweepToMainPanel(sweepCurrent - 1)
	Endif
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// Archived orphaned code fragment
//
// The following block was executable code outside any Function. Igor procedure files cannot safely
// compile loose analysis statements here, so it is kept as comments for historical reference.
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: ////////////////////////////////////////////////////////////////////////////////////////////////////
// ORPHANED_DISPLAY_FRAGMENT: //
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: //Parse out analysis waves
// ORPHANED_DISPLAY_FRAGMENT: tempstring1 = ParseFilePath (0,tempwave,":",0,2)
// ORPHANED_DISPLAY_FRAGMENT: If (cmpstr (tempstring1, "Avg")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:Avg:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select Average wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Elseif (cmpstr (tempstring1, "Concat")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:Concat:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select Concat wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Elseif (cmpstr (tempstring1, "FFT1")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:FFT1:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select FFT wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Elseif (cmpstr (tempstring1, "Hist1")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:Hist1:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select Hist1 wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Elseif (cmpstr (tempstring1, "ISI")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:Concat:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select ISI wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Elseif (cmpstr (tempstring1, "V")==0)
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:A:V:
// ORPHANED_DISPLAY_FRAGMENT: 	Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
// ORPHANED_DISPLAY_FRAGMENT: 	DoPrompt "Select V wave", inputwave
// ORPHANED_DISPLAY_FRAGMENT: Endif
// ORPHANED_DISPLAY_FRAGMENT: If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: 	Sprintf cmd, "PlotWaves /T /C/O/G %s", inputwave
// ORPHANED_DISPLAY_FRAGMENT: 	Execute cmd
// ORPHANED_DISPLAY_FRAGMENT: 	PPTGraphControl ()
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: 	SetDataFolder root:$(tempfilefolder):$(tempfolder)
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: Endif
// ORPHANED_DISPLAY_FRAGMENT:
// ORPHANED_DISPLAY_FRAGMENT: //For (n=i; n<(i+5); n+=1)
// ORPHANED_DISPLAY_FRAGMENT: accumwave = FileNameTruncated+"_"+num2str(i)+","
// ORPHANED_DISPLAY_FRAGMENT: //Endfor
// ORPHANED_DISPLAY_FRAGMENT: accumwave = RemoveEnding(accumwave, ",")
// ORPHANED_DISPLAY_FRAGMENT: AppendtoGraph $accumwave
// ORPHANED_DISPLAY_FRAGMENT:


// ****************************************************
//  control panel
// ****************************************************
Function Graph_Panel(ctrlName)
	string ctrlName
	Variable checknum
	Variable	barW = 1000		// width of control panel
	Variable	barH = 45			// height of control panel
	String		S_Value

	If(cmpstr(ctrlName,"")==0)
		ctrlName = WinName (0, 1)
	Else
		DoWindow /F $ctrlName
	Endif

	if (strlen (ctrlName) <= 0)
		Abort "The control panel will be installed into the top graph, but there aren't any graphs!"
	endif

	// resize graph to fit the control bar
	GetWindow $ctrlName, wsize
	if ((V_right - V_left) < barW)
		MoveWindow V_left, V_top, V_left + barW, V_bottom
	endif

	ControlBar barH


	Button pclose			pos = {20,5}, size = {60,30}, proc = CloseControl, title = "Close"

	Checkbox checkH1		pos={100,5}, title="No axes",mode=0, value=0, proc=Noaxes

	Checkbox checkH2		pos = {100,20},  title="Autoscale",mode=0, value=0, proc=Autoscale

	Checkbox checkH3		pos = {200,30},  disable=1, title="Display events", mode=0, value=0

	NVAR eventAmp = root:A:eventamp
	NVAR spikeamp = root:A:spikeamp
	Slider slider1			pos={180,0},size={80,45},proc=updateAmp, ticks=0,value=eventAmp,live=0, side=0,disable=1,limits={spikeamp,0,0}, title=""

	If (cmpstr(ctrlName,"tempGraph")==0)
		Button pfindpeakstemp		pos = {200,5}, size = {80,25}, disable = 1, proc = Find_Peaks2, title = "Events"
	Else
		Button pfindpeaks		pos = {200,5}, size = {80,25}, disable = 1, proc = Find_Peaks2, title = "Events"
	Endif


	Button pInstfreq		pos = {300,5}, size = {50,30}, disable = 1, proc = Inst_Freq2, title = "binISI"

	Button pAvgSpikes		pos = {300,5}, size = {80,30}, disable = 1, proc = Spikes_avg2, title = "binSpikes"

	Button phistogram		pos = {400,5}, size = {80,30}, disable = 1, proc = Hist2, title = "Histogram"

	//Button from Graph control panel (usually a concatenated graph)
	Button pvector1			pos = {500,5}, size = {80,30}, disable = 1, proc = vector2, title = "Vector"

	//Button from multiple sweeps w/ OUT cursors
	Button pvector2			pos = {500,5}, size = {80,30}, disable = 1, proc = vector2, title = "Vector"

	//Button from multiple sweeps w/ cursors
	Button pvector3			pos = {500,5}, size = {80,30}, disable = 1, proc = vector2, title = "Vector"

	Button ptonestart		pos = {600,5}, size = {80,30}, disable = 1, proc = Tone_Start, title = "Play Tones"

	Button pFFT				pos = {600,5}, size = {50,30}, disable = 1, proc = fft_wave1, title = "FFT"

	Button ppict			pos = {800,5}, size = {80,30}, proc = Save_Pict, title = "Save Pict"

	Button pbinary			pos = {900,5}, size = {80,30}, proc = Save_Binary, title = "Save Binary"



End

// ****************************************************
// checkbox: no axes: control panel
// ****************************************************

Function Noaxes (ctrlName,checked) : CheckBoxControl
	String	 ctrlName
	Variable checked

	//Get wave from wave in graph
	wave wave1 = WaveRefIndexed("",0,3)
	string inputname= NameofWave(wave1)
	string dfinputname = GetWavesDataFolder(wave1,1)
	string inputwave = dfinputname+inputname


	If  (checked==1)
		ModifyGraph tick=3,noLabel=2,axThick=0, margin=-1
		Hideinfo
		HideTools
		SetDrawLayer /K UserFront

	Else
		ModifyGraph tick=0,noLabel=0,axThick=1, margin=0
		Showinfo
		NVAR eventamp = root:A:eventamp
		SetDrawLayer UserFront
		SetDrawEnv xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
		DrawLine 0,eventAmp,1,eventAmp

	Endif
	ControlUpdate /A
End
// ****************************************************
// button: autoscale: control panel
// ****************************************************

Function Autoscale (ctrlName, checked) :CheckBoxControl
	String	 ctrlName
	Variable checked

	If (checked==1)
		SetAxis/A
		Checkbox checkH2 value=0
	Endif

End
// ****************************************************
// button: close: control panel
// ****************************************************

Function CloseControl (ctrlName) :ButtonControl
	String	 ctrlName
	String topGraph = WinName (0, 1)
	SetWindow $topGraph, hook = $""

	KillControl ptonestart
	KillControl pclose
	KillControl ppict
	KillControl pbinary
	KillControl checkH3
	ControlBar 0 //Removes Control Bar
	DoWindow /K $topGraph
End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//Update SLIDER1 -- spikeamp for event detection

Function updateAmp (ctrlName,value,event) : SliderControl
	String ctrlName
	Variable value	// value of variable as number
	Variable event
	NVAR eventamp = root:A:eventamp
	eventamp = value
	JTz_DrawEventThreshold(WinName(0, 1), eventamp)
End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//Update SLIDER2 -- spikeamp for event detection

Function updatemainAmp (ctrlName,value,event) : SliderControl
	String ctrlName
	Variable value	// value of variable as number
	Variable event
	NVAR eventAmp = root:A:eventamp
	eventAmp = value
	JTz_DrawEventThreshold("JT_Controls#embedwin", eventAmp)
	ControlUpdate /A /W=JT_Controls
End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
// Update SLIDER2 and eventamp and spikeamp
Function updatemain (ctrlName,varNum,varStr,varName) : SetVariableControl
	String ctrlName
	Variable varNum	// value of variable as number
	String varStr		// value of variable as string
	String varName	// name of variable
	NVAR eventAmp = root:A:eventamp
	eventAmp = varNum
	Slider slider2, win=JT_Controls, value=eventamp, limits={varNum,0,0}
	JTz_DrawEventThreshold("JT_Controls#embedwin", eventAmp)
	ControlUpdate /A /W=JT_Controls

End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
Function modifyGraphs(ctrlName): ButtonControl
	string ctrlName
	variable j,n,m
	string cmd
	variable tempvar1,tempvar2,tempvar3,tempvar4,tempvar5, tempvar6, tempvar7
	variable resolution=600
	variable width_cm=10
	variable height_cm=2
	variable linesize=0.5
	variable format
	variable width = width_cm*28.35 //28.35 points per cm or 72 points per inch
	variable height = height_cm*28.35

	NVAR protocol = root:A:protocol
	NVAR interval = root:A:interval


	//List all graphs
	String graphs=WinList("*",";","WIN:1") // A list of all graphs
	String topGraph = WinName(0, 1)	// Name of top graph

	If (itemsinlist(graphs)==0)
		Abort "No graphs to change!"
	ElseIf (itemsinlist(graphs)>1)
		Prompt tempvar1, "Select graph(s):", popup "Top graph; All graphs"
	Else
		Prompt tempvar1, "Change graph:", popup topGraph
	Endif
	Prompt tempvar2, "Change X-Axis Scaling:", popup "Don't change;Outer cursors;Full scale"
	Prompt tempvar3, "Change Axes:", popup "Don't change;Hide axes;Show axes"
	Prompt tempvar4, "Change Text Boxes:", popup "Don't change;Delete all text boxes;Delete textbox1;Delete textbox2;Delete textbox3"
	Prompt tempvar5, "Change Cursors:", popup "Don't change;Delete cursors;Add cursors"
	Prompt tempvar6, "Show/Hide Info:", popup "Don't change;Hide;Show"
	Prompt tempvar7, "Change Y-Axis Scaling:", popup "Don't change;Set values;Full scale"
	DoPrompt "Modify multiple graphs",tempvar1,tempvar2,tempvar3,tempvar4,tempvar5,tempvar6, tempvar7

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		If(tempvar5==3)
			variable cursornum=2
			variable startXval=0
			variable deltaXval=0.05
			Prompt cursornum, "Number of cursors:"
			Prompt startXval, "First cursor X value:"
			Prompt deltaXval, "X cursor spacing:"
			DoPrompt "Add Cursors to Graphs", cursornum, startXval,deltaXval
			If (V_flag!=0)	//if cancel clicked on DoPrompt, then set tempvar5 to 1
				tempvar5=1
			Endif
		Endif

		If (tempvar7==2)
			Variable topval = 4e-06
			Variable bottomval = -1e-05

			Prompt topval, "Top value:"
			Prompt bottomval, "Bottom value:"
			DoPrompt "Set Y-Axis boundaries:", topval,bottomval
		Endif

		If(tempvar1==1)
			graphs=topgraph+";"
		Endif

		//List all graphs
		For(j=0;j<itemsinlist(graphs);j+=1)
			string graph=stringfromlist(j,graphs)
			String graphtraces=TraceNameList(graph,";",1)
			String temptrace=stringfromlist(0,graphtraces)
			//Print temptrace

			//Set cursor strings and variables
			Variable leftval,rightval
			String cursorNames = "ABCDEFGHIJ"
			Variable numCursors = strlen(cursorNames)
			Variable numCursorsActual=0

			//Determine number of cursors on graph
			For (n=0; n<numCursors; n+=1)
				If (strlen(CsrInfo($(cursorNames[n]),graph))>0)
					numCursorsActual+=1
				Endif
			Endfor


			If(tempvar5==3) //Add new cursors

				If (numCursorsActual>0) //First delete any cursors on Graph
					For (m=0;m<numCursorsActual; m+=1)
						Cursor/W=$graph /K $(cursorNames[m])
					Endfor
				Endif
				Variable rval2
				rval2 = AddCursorsToGraph(graph,cursornum,temptrace,startXval,deltaXval,protocol)
				If (rval2 == 0)
					DoAlert 0, "zphys_display error: Bad value for number of cursors!"
				Elseif(rval2 == -1)
					DoAlert 0, "zphys_display error: Bad value for First cursor X value!"
				Elseif(rval2 == -2)
					DoAlert 0, "zphys_display error: Bad value for cursor spacing!"
				Elseif(rval2 == -3)
					DoAlert 0, "zphys_display error: Could not find the requested graph trace!"
				Else
					numCursorsActual=rval2
				Endif
			Endif

			////////////////////////////////////////////
			//Change X scale of graphs
			If (tempvar2==2)

				//Get the outermost cursors X values for scaling axis
				If (numCursorsActual>0)
					leftval = xcsr ($(cursorNames[0]),graph)
					rightval = xcsr ($(cursorNames[numCursorsActual-1]),graph)
				Else //No cursors on graphs so set limits to full scale
					leftval = DimOffset($temptrace, 0)
					rightval = DimSize($temptrace,0)*DimDelta($temptrace,0) //numpoints times deltax = x value of last point
				Endif
				SetAxis /W=$graph bottom, leftval, rightval

			Elseif(tempvar2==3) //Resize fullscale

				SetAxis /W=$graph /A=1 bottom
			Endif

			If(tempvar5==2) //Delete all cursors (now that we've finished scaling

				If (numCursorsActual>0) //Delete cursors on Graph
					For (m=0;m<numCursorsActual; m+=1)
						Cursor/W=$graph /K $(cursorNames[m])
					Endfor
				Endif
			Endif

			//////////////////////////////////////////

			////////////////////////////////////////////
			//Change Y scale of graphs
			If (tempvar7==2)
				SetAxis /W=$graph left, bottomval,topval

			Elseif(tempvar7==3) //Resize Y-axis fullscale
				SetAxis /W=$graph /A=1 left
			Endif

			//////////////////////////////////////////



			////Hide variouse parts of graphs
			If (tempvar3==2) //Hide axes
				ModifyGraph /W=$graph tick=3,noLabel=2,axThick=0, margin=-1
				Hideinfo /W=$graph
				HideTools /W=$graph /A

				SetDrawLayer /W=$graph /K UserFront  //delete find levels line if it exists, else it will delete graph!
			ElseIf (tempvar3==3) //Show axes
				ModifyGraph /W=$graph tick=0,noLabel=0,axThick=1, margin=0
				ShowInfo /W=$graph
			Endif

			//////////////////////////////////////////
			////Hide Info window of graphs
			If (tempvar6==2) //Hide Info
				Hideinfo /W=$graph
			ElseIf (tempvar6==3) //Show Info
				Showinfo /W=$graph
			Endif


			//////////////////////////////////////////
			////Delete text boxes
			If (tempvar4==2 || tempvar4==3)
				TextBox /W=$graph /K/N=textbox1 //delete text box
			Endif
			If(tempvar4==2 || tempvar4==4)
				TextBox /W=$graph /K/N=textbox2 //delete text box
			Endif
			If(tempvar4==2 || tempvar4==5)
				TextBox /W=$graph /K/N=textbox3 //delete text box
			Endif
		Endfor
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//ADAM LIGHT function



Function AddCursorsToGraph(graphName, numCursorsToAdd, traceNameToAddTo, startXval, deltaXval, protocol)
	String graphName
	Variable numCursorsToAdd
	String traceNameToAddTo
	Variable startXval
	Variable deltaXval
	Variable protocol

	NVAR interval = root:A:interval

	String cursorNames = "ABCDEFGHIJ"
	Variable numCursors = strlen(cursorNames)
	Variable n, i
	Variable leftval, rightval

	If (strlen(graphName) == 0 || strlen(traceNameToAddTo) == 0)
		Return -3
	Endif

	WAVE /Z traceWaveFromGraph = TraceNameToWaveRef(graphName, traceNameToAddTo)
	If (WaveExists(traceWaveFromGraph))
		leftval = DimOffset(traceWaveFromGraph, 0)
		rightval = DimOffset(traceWaveFromGraph, 0) + (DimSize(traceWaveFromGraph, 0) - 1) * DimDelta(traceWaveFromGraph, 0)
	Else
		WAVE /Z traceWaveByName = $(traceNameToAddTo)
		If (!WaveExists(traceWaveByName))
			Return -3
		Endif
		leftval = DimOffset(traceWaveByName, 0)
		rightval = DimOffset(traceWaveByName, 0) + (DimSize(traceWaveByName, 0) - 1) * DimDelta(traceWaveByName, 0)
	Endif

	If (numtype(numCursorsToAdd) != 0 || numCursorsToAdd < 1)
		Return 0
	ElseIf (numCursorsToAdd > numCursors)
		numCursorsToAdd = numCursors
		DoAlert 0, "zPhys display: number of cursors trimmed to max number of cursors (" + num2str(numCursors) + ")."
	Endif

	If (deltaXval <= 0 && numCursorsToAdd > 1)
		Return -2
	Endif
	If ((startXval < leftval || startXval > rightval) && protocol != 3)
		Return -1
	ElseIf (((startXval + ((numCursorsToAdd - 2) * deltaXval)) > rightval) && protocol == 3)
		DoAlert 0, "zPhys display: bad startXval or deltaXval for paired-cursor protocol."
		Return -2
	ElseIf (((startXval + ((numCursorsToAdd - 1) * deltaXval)) > rightval) && protocol != 3)
		DoAlert 0, "zPhys display: bad startXval or deltaXval."
		Return -2
	Endif

	If (protocol != 3)
		For (n = 0; n < numCursorsToAdd; n += 1)
			Cursor /H=2 /S=1 /C=(65535,0,0) /W=$graphName $(cursorNames[n]), $traceNameToAddTo, startXval + n * deltaXval
		Endfor
		Return numCursorsToAdd
	Else
		For (i = 0; i < (numCursorsToAdd / 2); i += 1)
			For (n = i; n < (i + 2); n += 1)
				Cursor /H=2 /S=1 /C=(65535,0,0) /W=$graphName $(cursorNames[n + i]), $traceNameToAddTo, startXval + n * deltaXval + i * interval
			Endfor
		Endfor
		Return numCursorsToAdd
	Endif
End
////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//////\\\\\\\\/////////\\\\\\\///////\\\\\\\\///
//From Nate Hyde at Wavemetrics 02/24/2014
// Uses the Scatter Dot Plot package data to add a category plot to an existing graph

Function addCategoryToSDP(ctrlName) : ButtonControl
	String ctrlName
	String graphName = ""
	String tempvar1

	If (cmpstr(ctrlName, "button210") == 0)
		ScatterDotPlot#ScatterDotPlotPanel()
		Return 1
	Endif

	String graphs = WinList("*", ";", "WIN:1")
	String topGraph = WinName(0, 1)
	If (ItemsInList(graphs) == 0)
		Abort "No graphs to add category plot to."
	ElseIf (ItemsInList(graphs) == 1)
		graphName = topGraph
	Else
		Prompt tempvar1, "Graphs:", popup graphs
		DoPrompt "Select Scatter Dot Plot graph to add category plot to:", tempvar1
		If (V_flag != 0)
			Return -1
		Endif
		graphName = tempvar1
	Endif

	If (strlen(graphName) == 0)
		Abort "No graph was selected."
	Endif

	DFREF graphPkgDFR = ScatterDotPlot#WMGetScatterDotPlotGraphDFR(graphName=graphName)
	Wave /T baseWaveNames = graphPkgDFR:selectedWaveNames
	Wave /T tickNames = graphPkgDFR:tickWaveNames

	Variable nCategories = DimSize(baseWaveNames, 0)
	Variable i

	Make /O /N=(nCategories) graphPkgDFR:WM_CategoryMeans
	Make /O /N=(nCategories) graphPkgDFR:WM_CategoryStdDev
	Wave meanVals = graphPkgDFR:WM_CategoryMeans
	Wave stdDevVals = graphPkgDFR:WM_CategoryStdDev

	For (i = 0; i < nCategories; i += 1)
		Wave currWave = $(baseWaveNames[i])
		WaveStats /Q currWave
		meanVals[i] = V_avg
		stdDevVals[i] = V_sdev
	Endfor

	DoWindow /F $graphName
	AppendToGraph /W=$graphName /T meanVals vs tickNames
	ModifyGraph /W=$graphName hbFill=0, lsize(WM_CategoryMeans)=1, useNegRGB(WM_CategoryMeans)=1
	ModifyGraph /W=$graphName usePlusRGB(WM_CategoryMeans)=1, rgb(WM_CategoryMeans)=(0,0,0)
	ModifyGraph /W=$graphName noLabel(top)=2, axRGB(top)=(65535,65535,65535), standoff(bottom)=0
	SetAxis /W=$graphName left 0, *
	SetAxis /W=$graphName bottom 0.5, nCategories + 0.5
	ErrorBars /T=1 /L=1 /W=$graphName WM_CategoryMeans Y, wave=(stdDevVals, stdDevVals)
End

////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////
