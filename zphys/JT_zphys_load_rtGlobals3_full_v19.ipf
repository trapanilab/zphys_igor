#pragma rtGlobals=3        // Full Igor Pro 9 cleanup version.

// =================================================================================================
// JT_zphys_load.ipf
// -------------------------------------------------------------------------------------------------
// Data-loading and import routines for the zPhys analysis panel.
//
// Primary responsibilities:
//   - Load CSV waves.
//   - Import HEKA/PatchMaster data through SutterPatch import or the older LoadPM workflow.
//   - Load SutterPatch 2D waves into the zPhys folder organization.
//   - Read/import Axon ABF data using the legacy binary-header reader in this file.
//   - Update the JT_Controls panel after a file/series/wave is loaded.
//
// Dependencies and expectations:
//   - Start_A() in JT_zphys_panel.ipf should have initialized root:A globals first.
//   - The main panel window is named JT_Controls and contains the embedded graph JT_Controls#embedwin.
//   - HEKA import depends on SutterPatch#PMImport_LoadBundle, or on the legacy LoadPM command for
//     the older Read_HEKA_Folder/Import_HEKA_Data path.
//   - ABF import depends on GBLoadWave and the fixed-offset ABF header reader below.
//
// Conservative cleanup notes:
//   - This variant switches the procedure file to rtGlobals=3 for stricter checking.
//   - Function names and public callbacks are intentionally preserved.
//   - Folder/wave naming conventions are intentionally preserved.
//   - Repeated panel-update code is left in place to reduce risk; see cleanup notes for refactor ideas.
// =================================================================================================

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// -------------------------------------------------------------------------------------------------
// AddWaves2D
// Combine all *_Adc-1 waves in the current data folder into the first wave as a 2D wave.
// The first source wave becomes column 0; each subsequent source wave is copied into the next column
// and then removed. This is a utility/temporary function and is not called by the main panel UI.
Function AddWaves2D(ctrlName)
	String ctrlName

	String listOfWaves = WaveList("*_Adc-1", ";", "")
	If (cmpstr(listOfWaves, "") == 0)
		Abort "No *_Adc-1 waves found in the current folder."
	EndIf

	Variable numOfWaves = ItemsInList(listOfWaves)
	String outputWaveName = StringFromList(0, listOfWaves)
	Wave outputWave = $outputWaveName
	Redimension /N=(-1, numOfWaves) outputWave

	Variable i
	For (i = 1; i < numOfWaves; i += 1)
		String sourceWaveName = StringFromList(i, listOfWaves)
		Wave sourceWave = $sourceWaveName
		outputWave[][i] = sourceWave[p]
		KillWaves sourceWave
	EndFor
End


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////



////////////////////////////////////////////////////////////////////////////////////////////////////
// Import_PXP_File
// Load a SutterPatch Igor packed experiment (.pxp) into the current experiment.
// The imported top-level data folder is named from the selected PXP filename, then the usual
// SutterPatch wave-selection workflow is launched.
Function Import_PXP_File(ctrlName): ButtonControl
	String ctrlName

	String tempFileSelection = ""
	Variable refnum

	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempfolder = root:A:tempfolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	Open /R/D/T=".pxp"/M="Select a SutterPatch Igor experiment (*.pxp)" refnum
	tempFileSelection = S_fileName
	If (strlen(tempFileSelection) == 0)
		Abort "No PXP file selected."
	EndIf

	String fileBaseName = ParseFilePath(3, tempFileSelection, ":", 0, 0)
	String requestedFolderName = JT_CleanPXPFolderName(fileBaseName)
	String importFolderName = JT_UniqueRootFolderName(requestedFolderName)

	If (cmpstr(importFolderName, requestedFolderName) != 0)
		Print "Root folder " + requestedFolderName + " already exists; importing PXP into " + importFolderName + " instead."
	EndIf

	Print "\r" + date() + ": Import_PXP_File loading " + tempFileSelection + " into root:" + importFolderName + ": at " + time()

	// LoadData loads packed-experiment data into the current experiment. /R keeps subfolders.
	// IMPORTANT: /T=$importFolderName uses the string variable. Without $, Igor creates
	// a literal root:importFolderName: folder.
	SetDataFolder root:
	LoadData /O=2 /Q /R /T=$importFolderName tempFileSelection
	If (V_flag < 0)
		Abort "PXP load was canceled."
	EndIf

	String sutterPatchRoot = JT_FindImportedSutterPatchRoot(importFolderName)
	If (strlen(sutterPatchRoot) == 0)
		Abort "The selected PXP loaded into root:" + importFolderName + ":, but no SutterPatch:Data folder was found. Looked at root:" + importFolderName + ":SutterPatch:Data and one nested folder level."
	EndIf

	NewDataFolder /O root:SUTTER
	String /G root:A:pxpSutterPatchRoot
	SVAR pxpSutterPatchRoot = root:A:pxpSutterPatchRoot
	pxpSutterPatchRoot = sutterPatchRoot
	tempfilefolder = importFolderName
	tempfolder = ""
	tempwave = ""
	input_type = ""
	stim_type = ""
	data_type = "SUTTER"

	// Hand off to the standard SutterPatch loader, now pre-seeded with the imported PXP folder.
	Load_Sutter_Wave("LoadPXP")
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// JT_CleanPXPFolderName
// Convert a selected PXP filename into a safe Igor top-level data-folder name.
Function/S JT_CleanPXPFolderName(fileBaseName)
	String fileBaseName

	String folderName = fileBaseName
	String lowerFolderName = LowerStr(folderName)
	Variable dotPos = strsearch(lowerFolderName, ".pxp", 0)
	If (dotPos > 0)
		folderName = folderName[0, dotPos-1]
	EndIf

	folderName = CleanupName(folderName, 0)
	If (strlen(folderName) == 0)
		folderName = "LoadedPXP"
	EndIf

	If (char2num(folderName[0]) < 65)
		folderName = "X" + folderName
	EndIf

	Return folderName
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// JT_UniqueRootFolderName
// Return baseName if it is unused, otherwise append _1, _2, ... to avoid overwriting an existing root folder.
Function/S JT_UniqueRootFolderName(baseName)
	String baseName

	String candidate = baseName
	Variable suffix = 1
	Do
		If (!DataFolderExists("root:" + candidate))
			Return candidate
		EndIf
		candidate = baseName + "_" + num2str(suffix)
		suffix += 1
	While (suffix < 10000)

	Abort "Could not create a unique folder name for the selected PXP file."
	Return baseName
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// JT_FindImportedSutterPatchRoot
// Return the SutterPatch container path inside an imported PXP folder.
// Most SutterPatch PXPs load as root:<filename>:SutterPatch:, but some packed
// experiments preserve one additional top-level data folder. This helper supports
// both layouts without renaming user data folders.
Function/S JT_FindImportedSutterPatchRoot(importFolderName)
	String importFolderName

	String importRoot = "root:" + PossiblyQuoteName(importFolderName) + ":"
	String directSutterRoot = importRoot + "SutterPatch:"
	If (DataFolderExists(directSutterRoot + "Data"))
		Return directSutterRoot
	EndIf
	If (DataFolderExists(directSutterRoot + "Data:Analysis"))
		Return directSutterRoot
	EndIf

	Variable index = 0
	Do
		String childFolderName = GetIndexedObjName(importRoot, 4, index)
		If (strlen(childFolderName) == 0)
			Break
		EndIf

		String nestedSutterRoot = importRoot + PossiblyQuoteName(childFolderName) + ":SutterPatch:"
		If (DataFolderExists(nestedSutterRoot + "Data"))
			Return nestedSutterRoot
		EndIf
		If (DataFolderExists(nestedSutterRoot + "Data:Analysis"))
			Return nestedSutterRoot
		EndIf
		index += 1
	While (1)

	Return ""
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// JT_DefaultSutterDataSubfolder
// Return the SutterPatch data subfolder to use for routine selection.
// The common case is Data:. If only Data:Analysis: exists, use it as a fallback and print a note.
Function/S JT_DefaultSutterDataSubfolder(sutterPatchRoot)
	String sutterPatchRoot

	If (DataFolderExists(sutterPatchRoot + "Data"))
		Return "Data:"
	EndIf

	If (DataFolderExists(sutterPatchRoot + "Data:Analysis"))
		Print "No SutterPatch Data: folder was found at " + sutterPatchRoot + ". Using Data:Analysis: instead."
		Return "Data:Analysis:"
	EndIf

	Abort "No SutterPatch Data: or Data:Analysis: folder was found at " + sutterPatchRoot
	Return ""
End

// -------------------------------------------------------------------------------------------------
// Import_CSV_File
// Load a single CSV file using Igor's LoadWave command. Loaded waves are prefixed with csv_<filename>.
Function Import_CSV_File(ctrlName)	// Button Control

	String ctrlName
	String tempFileSelection = ""
	Variable refnum
	Print "\r"+Date()+": Import_CSV_File function called at "+Time()

	Open /R/D/T=".csv" /MULT=0 refnum
	tempFileSelection = S_fileName
	Print tempFileSelection

	If (strlen(tempFileSelection) == 0)
		Abort "No file(s) selected"
	Else
		String tempfilename = ParseFilePath (3,tempFileSelection,":",0,0)
		LoadWave /A=$("csv_"+tempfilename) /H /J /K=1 /Q /O tempFileSelection
		If(V_flag>1)
			Print num2str(ItemsInList(S_waveNames))+" waves loaded from CSV file"
			//tempWave = StringFromList(i, S_waveNames, "\r")
		EndIf
	EndIf

End

////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// Import_HEKA_File
// Import a HEKA .dat file through SutterPatch import and move the loaded waves into a file-named folder.
Function Import_HEKA_File (ctrlName)	//Button Control

	String ctrlName
	Variable StatusCheck
	String cmd
	String tempFileSelection=""
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	variable refnum

	//December 15, 2021
	//Using the SUTTERPATCH IMPORT feature to import HEKA file given 64-bit OS and Igor no longer works with PPT.XOP

	#If(exists("SutterPatch#PMImport_LoadBundle") == 6)

	print "\r"+date()+": Import_HEKA_File function called at "+time()+" Using SutterPatch Import function to load waves..."


	//Open the file to be loaded; prompt the user to select a file if tempFileSelection did not pass a file path to this function
	If (strlen(tempFileSelection)==0)
		Open /D/T=".dat"/M="Select a HEKA *.dat file" /P= HEKAPath /R refnum
		Open /R/Z refnum as S_filename
	Else
		Open /R/Z refnum as tempFileSelection
	EndIf
	If (V_flag!=0)		//Check to make sure that the user chose a file; if user hits cancel, the function quits here
		return -1		//Indicates failure
	EndIf

	tempFileSelection = S_fileName

	//set HEKAPath to new location
	String tempPath2 = ParseFilePath (1,tempFileSelection,":",1,0)
	NewPath /O /Q HEKAPath, tempPath2


	//Create truncated File Name and temporarily hold it in tempstring1
	String tempstring1 = ParseFilePath (3,tempFileSelection,":",0,0)

	//If file name begins with a number, the letter "X" will be appended to the beginning of it
	If (char2num(tempstring1[0])<65)
		tempstring1[0]="X"
	EndIf

	Close refnum

	//load HEKA file with SUTTERPATCH IMPORT
	//From Jan Dolzer 12/14/21: "The command for SutterPatch import using the file selector is SutterPatch#PMImport_MergeDataFile().
	//Since SutterPatch runs in an independent module, you do need the prefix SutterPatch#.
	//If you want your code to pass the file name, use the following syntax:"

	
	SutterPatch#PMImport_LoadBundle(tempFileSelection)
	
	NewDataFolder /O root:$(tempstring1)
	NewDataFolder /O root:$(tempstring1):SutterPatch
	NewDataFolder /O root:$(tempstring1):SutterPatch:Data
	String dfnew = "root:"+tempstring1+":SutterPatch:Data:"
	String load_folder = "root:SutterPatch:Data:"

	String tempwavename
	Variable index=0


	//Move all loaded waves to a folder named as the filename
	string waveslist=WaveList("!E*", ";", "", root:SutterPatch:Data) // A list of all Waves in data folder
	For(index=0;index<itemsinlist(waveslist);index+=1)
		tempwavename=stringfromlist(index,waveslist)
		Wave w = $(load_folder+tempwavename)
		MoveWave w, $dfnew
	EndFor
	KillWaves /Z root:SutterPatch:Data:ExperimentStructure
	
	#Else
	
	Abort "Must load SutterPatch at startup in order to use this import HEKA function" 
	
	
	#EndIf


	//EVERYTHING BELOW IS NO LONGER USED AS NOW THE SUTTERPATCH IMPORT FUNCTION WILL READ HEKA FILE INTO IGOR AND IMPORT SUTTER button WILL BE USED 12/15/2021
	//Add functions so that data from one file is entered into folder named after that file
	//	StatusCheck = Read_HEKA_Folder(tempFileSelection)
	//
	//	If (StatusCheck >=0)
	//		Import_HEKA_Data(statuscheck)  //default Series=1
	//	Else
	//		print "Cancelled: HEKA file not loaded."
	//	EndIf
End


////////////////////////////////////////////////////////////////////////////////////////////////////


// -------------------------------------------------------------------------------------------------
// Import_HEKA_Series
// Load the next HEKA series using the legacy LoadPM-based HEKA workflow.
Function Import_HEKA_Series (ctrlName)	//Button Control

	String ctrlName

	Print "\r"+Date()+": Import_HEKA_Series function called at "+Time()
	NVAR /Z pptActSeries
	If (NVAR_Exists(pptActSeries) == 0)
		Abort "No active HEKA series is available. Load a HEKA file/series first."
	EndIf
	Import_HEKA_Data(pptActSeries + 1)
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// Read_HEKA_Folder
// Read HEKA/PatchMaster file metadata with LoadPM /U and prepare root:HEKA globals for series import.
Function Read_HEKA_Folder (tempFileSelection)

	string tempFileSelection
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	string cmd
	variable refnum

	//Open the file to be loaded; prompt the user to select a file if tempFileSelection did not pass a file path to this function
	If (strlen(tempFileSelection)==0)
		Open /D/T=".dat"/M="Select a HEKA *.dat file" /P= HEKAPath /R refnum
		Open /R/Z refnum as S_filename
	Else
		Open /R/Z refnum as tempFileSelection
	EndIf
	If (V_flag!=0)		//Check to make sure that the user chose a file; if user hits cancel, the function quits here
		return -1		//Indicates failure
	EndIf
	tempFileSelection = S_fileName

	//set HEKAPath to new location
	String tempPath2 = ParseFilePath (1,tempFileSelection,":",1,0)
	NewPath /O /Q HEKAPath, tempPath2


	//Create truncated File Name and temporarily hold it in tempstring1
	String tempstring1 = ParseFilePath (3,tempFileSelection,":",0,0)

	//If file name begins with a number, the letter "x" will be appended to the beginning of it
	If (char2num(tempstring1[0])<65)
		tempstring1[0]="X"
	EndIf

	//Create data folder named after truncated file name to hold all waves and variables associated with the selected file
	NewDataFolder /O/S root:HEKA //$(tempstring1)

	//String /G baseFileNameshort = ParseFilePath (0,tempFileSelection,":",1,0)				//Global string containing file name of selected file
	String /G baseFileNameTruncated = tempstring1			//Global string containing file name of selected file minus ".dat"
	String /G baseFileName = tempFileSelection		//Global string containing path to selected file + file name


	//Set tempfilefolder to the container folder for a given experiment
	tempfilefolder = "HEKA"
	Close refnum

	//load PM file with /U flag to determine number of groups and series
	Sprintf cmd, "LoadPM /Q/U \"%s\"",baseFileName
	Execute cmd
	NVAR pptSeries
	print "Loading  Data File...wait..."+num2str(pptSeries)+" series in file"

	return 1		//Signifies success
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// Import_HEKA_Data
// Load selected HEKA sweeps/inputs into 2D waves and update the panel display state.
Function Import_HEKA_Data (currentseries)
	Variable currentseries //pass pptActseries+1 if "Load_Series" used; else 1 is passed from "Load_File"

	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	SVAR baseFileNameTruncated = root:$(tempfilefolder):baseFileNameTruncated
	SVAR baseFileName = root:$(tempfilefolder):baseFileName
	string cmd, tempstring1, tempstring2

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	NVAR Gain1 = root:A:extraGain1
	NVAR Gain2 = root:A:extraGain2
	SVAR Gain = root:A:extraGain

	Variable wavescale1 = Gain1
	Variable wavescale2 = Gain2
	string tempScaleWave

	variable tempa = 1  //change this if acquisition is other than 1
	variable tempb = currentseries //pass pptActseries+1 on to tempb
	variable tempsweepStartnum = 1
	variable tempsweepEndnum = 60
	variable tempd
	variable i,n,j,baseval,checknum

	String currentDF = GetDataFolder(1)	// Save

	If (cmpstr(data_type,"SUTTER")==0)
		Abort "Load Series is under development for Sutter Data"
	EndIf

	SetDataFolder root:$(tempfilefolder)
	NVAR /Z pptActGroup,pptActSeries,pptActSweep,pptActTrace
	NVAR /Z pptGroups,pptSeries,pptSweeps,pptTraces

	If (pptGroups>1)
		Prompt tempa, "Select Group#:"
		DoPrompt "There are "+num2str(pptGroups)+" groups in this Heka File", tempa
	EndIf

	Prompt tempb, "Load Series #:"
	Prompt tempsweepStartnum, "Start sweep:"
	Prompt tempsweepEndnum, "End sweep:"
	Prompt tempd, "Input", popup "Input1 (e.g., I-mon);Input2 (e.g., Vmon);Input3"
	Prompt tempScaleWave, "Scale Wave?", popup Gain+";no;yes"
	DoPrompt "There are "+num2str(pptSeries)+" series in this Heka File", tempb,tempsweepStartnum,tempsweepEndnum, tempd,tempScaleWave

	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc

		//End  here if the series requested is larger than the number of series
		If(tempb>pptSeries)
			SetDataFolder currentDF
			Abort "No such Series found! There are "+num2str(pptSeries)+" series in this Heka File"
		EndIf

		//Display panel to indicate data is loading.
		NewPanel /N=FileLoadWin /FLT=2 /W=(800,400,1000,450) as "Loading..."
		ModifyPanel cbRGB=(30583,30583,30583), frameStyle=1, NoEdit=1
		DrawText 21,20,"Please wait.."
		SetActiveSubwindow _endfloat_
		DoUpdate

		//Make Series Folder and set Global Variables
		tempfolder = baseFileNameTruncated+"_"+num2str(tempb)
		String seriesDataFolder = "root:"+tempfilefolder+":"+tempfolder

		If (DataFolderExists(seriesDataFolder)!=1)
			NewDataFolder /O /S $seriesDataFolder
			Variable /G sweepTime //0 = absolute time
			String /G FileNameTruncated
		Else
			SetDataFolder $seriesDataFolder
			NVAR /Z sweepTime
			SVAR /Z FileNameTruncated, input1_type, input2_type, input3_type, stim1_type, stim2_type, stim3_type
		EndIf

		//Read the DATA file Series with /U to determine tempa and tempb
		Sprintf cmd, "LoadPM /Q/U/A=%d/B=%d  \"%s\"",tempa, tempb,baseFileName
		Execute cmd
		NVAR /Z pptActGroup,pptActSeries,pptActSweep,pptActTrace
		NVAR /Z pptGroups,pptPulseTime,pptSeries,pptSweeps,pptTraces

		If (tempsweepEndnum>pptSweeps)
			print "Attempting to load too many ("+num2str(tempsweepEndnum-tempsweepStartnum+1)+") sweeps from "+num2str(pptSweeps-tempsweepStartnum+1)+" available sweeps..fixing."
			tempsweepEndnum=pptSweeps
		Else
			print "Loaded "+num2str(tempsweepEndnum-tempsweepStartnum+1)+" sweeps from "+num2str(pptSweeps)+" total sweeps."
		EndIf

		//Update the Global Variables
		sweepStartnum = tempsweepStartnum
		sweepEndnum = tempsweepEndnum
		sweepCurrent = tempsweepStartnum
		sweepTime = 0	//0 = absolute time
		data_type = "HEKA"


		//Scale Wave if needed
		If(cmpstr(tempScaleWave,"yes")==0)
			Prompt wavescale1, "V-mon scale (e.g., 10X or 100X)"
			Prompt wavescale2, "Addtl gain (e.g., for Brownlee @ 100X)"
			Doprompt "Scale incoming sweeps", wavescale1,wavescale2

			//Update the Global Variables
			Gain1 = wavescale1
			Gain2 = wavescale2
			Gain = tempScaleWave
		EndIf


		//Read 1st sweep to determine "traces" (inputs)
		Sprintf cmd, "LoadPM /Q/U/A=%d/B=%d /C=%d  \"%s\"",tempa, tempb,tempsweepStartnum,baseFileName
		Execute cmd
		If (pptTraces<tempd)
			KillWindow /Z FileLoadWin // Kill panel
			SetDataFolder currentDF
			Abort "Aborted. Attempted to load ("+num2str(tempd)+") input from "+num2str(pptTraces)+" available inputs."
		Else
			Print "Loaded "+num2str(pptTraces)+" traces (inputs)."
		EndIf


		/////////////////////////////////////////////////////////////////////////////////////////////////
		/////////////////////////////////////////////////////////////////////////////////////////////////
		//Determine if Wave was already loaded and delete it before renaming incoming wave
		tempstring1 = FileNameTruncated+input_type
		If (WaveExists($tempstring1)==1)  //Close embeded graph in order to killwaves
			string graphs=WinList("*",";","WIN:1") // A list of all graphs
			For(j=0;j<itemsinlist(graphs);j+=1)
				string graph=stringfromlist(j,graphs)
				string traces=TraceNameList(graph,";",1)
				string tracematch = listmatch(traces,tempstring1)
				If(cmpstr(tracematch,"")!=0) // Assumes that each wave is plotted at most once on a graph.
					Print "Wave is in graph "+graph+" ... killing graph "
					//RemoveFromGraph /W=$graph $tempwave
					KillWindow $graph
				EndIf
			EndFor
		EndIf
		/////////////////////////////////////////////////////////////////////////////////////////////////
		/////////////////////////////////////////////////////////////////////////////////////////////////

		//Strings for loading sweeps
		String stimwave_string,inputwave_string
		String tempscan_string1,tempscan_string2
		String WaveList1
		String tempinput_type,tempstim_type
		FileNameTruncated = baseFileNameTruncated +"_"+num2str(tempb)


		//NOTE! Sweeps are opened with absolute time (/T)
		For (i=tempsweepStartnum; i<=tempsweepEndnum; i+=1)

			Sprintf cmd, "LoadPM /Q/I/T/O /N=%s /A=%d/B=%d /C=%d /D=%d \"%s\"", baseFileNameTruncated, tempa, tempb, i, tempd, baseFileName
			Execute cmd

			If (i==tempsweepStartnum) //on 1st sweep determine inputs

				tempscan_string1 = baseFileNameTruncated+"_"+num2str(tempa)+"_"+num2str(tempb)+"_"+num2str(i)+"_"+num2str(tempd)+"_%s"
				tempscan_string2 = baseFileNameTruncated+"_"+num2str(tempa)+"_"+num2str(tempb)+"_"+num2str(i)+"_"+num2str(tempd)+"*"
				WaveList1 = WaveList(tempscan_string2,";","")

				inputwave_string = StringFromList(0,WaveList1) //item 0 is the 1st input wave
				stimwave_string = StringFromList(1,WaveList1)  //second item is the stim wave

				sscanf inputwave_string,tempscan_string1,tempinput_type
				sscanf stimwave_string, tempscan_string1,tempstim_type

				//Determine Input1 type
				If ((tempd==1)&&(strsearch(tempinput_type,"DA",0)==-1))
					String /G input1_type = "_"+tempinput_type
					String /G stim1_type = "_"+tempstim_type
				ElseIf (tempd==1)
					String /G input1_type = "_"+tempstim_type
					String /G stim1_type = "_"+tempinput_type
				EndIf

				//Determine Input2 type
				If ((tempd==2)&&(strsearch(tempinput_type,"DA",0)==-1))
					String /G input2_type = "_"+tempinput_type
					String /G stim2_type = "_"+tempstim_type
				ElseIf (tempd==2)
					String /G input2_type = "_"+tempstim_type
					String /G stim2_type = "_"+tempinput_type
				EndIf

				//Determine Input3 type
				If ((tempd==3)&&(strsearch(tempinput_type,"DA",0)==-1))
					String /G input3_type = "_"+tempinput_type
					String /G stim3_type = "_"+tempstim_type
				ElseIf (tempd==3)
					String /G input3_type = "_"+tempstim_type
					String /G stim3_type = "_"+tempinput_type
				EndIf

				If (tempd==1)
					input_type = input1_type
					stim_type= stim1_type
				ElseIf(tempd==2)
					input_type= input2_type
					stim_type= stim2_type
				ElseIf(tempd==3)
					input_type= input3_type
					stim_type= stim3_type
				EndIf

			EndIf

			//temporary string for each loaded wave
			tempstring1 = baseFileNameTruncated+"_"+num2str(tempa)+"_"+num2str(tempb)+"_"+num2str(i)+"_"+num2str(tempd)+input_type
			wave wave1 = $(tempstring1)

			If (cmpstr(stim_type,"")!=0)
				tempstring2 = baseFileNameTruncated+"_"+num2str(tempa)+"_"+num2str(tempb)+"_"+num2str(i)+"_"+num2str(tempd)+stim_type
				wave /Z wave2 = $(tempstring2)
			EndIf

			If(cmpstr(tempScaleWave,"yes")==0)
				wave1 = wave1/(wavescale1*wavescale2)
			EndIf

			//If Baseline is checked then baseline subtract the wave
			controlInfo /W=JT_Controls check000
			checknum = V_Value
			If  (checknum==1)
				baseval = mean (wave1)//(wave1,0,0.1)
				wave1 = (wave1-baseval)
			EndIf

			//Create a 2D wave to store all loaded sweeps from the series
			If (i==tempsweepStartnum)
				String tempstring2D1 = FileNameTruncated+input_type
				Duplicate /O wave1 $tempstring2D1
				Wave wave2D1 = $(tempstring2D1)
				Redimension /N=(-1, tempsweepEndnum) wave2D1
				wave2D1 = NaN
				wave2D1[][i-1] = wave1[p]

				//If stimulus wave present
				If (cmpstr(stim_type,"_")!=0)
					String tempstring2D2 = FileNameTruncated+stim_type
					Duplicate /O wave2 $tempstring2D2
					Wave wave2D2 = $(tempstring2D2)
					Redimension /N=(-1, tempsweepEndnum) wave2D2
					wave2D2 = NaN
					wave2D2[][i-1] = wave2[p]
				EndIf


			Else	//Add subsequent waves to 2D wave
				wave2D1[][i-1] = wave1[p]

				//If stimulus wave present
				If (cmpstr(stim_type,"_")!=0)
					wave2D2[][i-1] = wave2[p]
				EndIf
			EndIf
			KillWaves wave1
			KillWaves /Z wave2
		EndFor //END THE LOAD WAVES LOOP

		//Write the sweep name and numbers to SVAR and NVARs
		tempwave = FileNameTruncated+input_type
		pptActSweep = tempsweepStartnum
		pptSweeps = tempsweepEndnum		// Keep absolute sweep numbering for the 2D wave columns.

		Load_HEKA_Wave ("Import_HEKA_File",pptActSweep)

		Print "Last wave loaded into "+tempstring2D1+"was "+tempstring1
		KillWindow /Z FileLoadWin			// Kill panel

	Else
		SetDataFolder currentDF
	EndIf
End

////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// Load_HEKA_Wave
// Display a selected HEKA sweep from the active 2D wave and refresh zPhys panel globals/controls.
Function Load_HEKA_Wave (ctrlName,ctrlNum)

	String ctrlName
	Variable ctrlNum
	Variable n
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	SetDataFolder root:$(tempfilefolder):$(tempfolder)
	SVAR FileNameTruncated
	SVAR /Z input1_type
	SVAR /Z input2_type
	SVAR /Z input3_type
	SVAR /Z stim1_type
	SVAR /Z stim2_type
	SVAR /Z stim3_type

	NVAR /Z pptActTrace
	NVAR /Z pptActSweep
	NVAR /Z pptSweeps
	NVAR /Z sweepTime

	//Update gloabal variables in /A
	sweepStartnum = pptActSweep
	sweepEndnum = pptSweeps //could use DimSize of 2Dwave
	sweepCurrent = ctrlNum

	If (pptActTrace==1)
		input_type = input1_type
		stim_type= stim1_type
	ElseIf(pptActTrace==2)
		input_type= input2_type
		stim_type= stim2_type
	ElseIf(pptActTrace==3)
		input_type= input3_type
		stim_type= stim3_type
	EndIf

	tempwave = FileNameTruncated+input_type
	Wave twoDWave = $tempwave


	//Find peak amplitude in a sample trace to pass to the Find Levels procedure
	MatrixOP/FREE firstcol = col(twoDWave, 0)
	SetScale /P x 0,DimDelta(twoDWave, 0 ),"s", firstcol

	Wavestats /Q firstcol
	Variable tempstatsvar1 = -10* V_adev //make signal detection negative and 10 times the background noise
	Variable tempWavemin = V_min

	FindPeak /Q /B=1 /M=(tempstatsvar1) /N firstcol

	If (cmpstr(num2str(V_PeakVal),"NaN")==0)
		spikeamp = tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = 100e-6
	Else
		spikeamp = tempWavemin
		eventAmp = 0.65*V_PeakVal
		spiketime = V_PeakWidth
	EndIf

	string popStrpath
	popStrpath = tempfilefolder+":"+tempfolder
	UpdateControlPanel (ctrlName, popStrpath,1)

	//Add trace to panel graph
	AppendToGraph /W=JT_Controls#embedwin $tempwave[][sweepCurrent-1] //Wave0 ==sweep 1
	ModifyGraph /W=JT_Controls#embedwin rgb = (0,0,0)
	SetVariable setvar0, win=JT_Controls, value= spiketime
	SetVariable setvar1, win=JT_Controls, value= spikeamp
	SetVariable setvar2, win=JT_Controls, value= sweepStartnum
	SetVariable setvar3, win=JT_Controls, value= sweepEndnum
	SetVariable setvar4, win=JT_Controls, value= sweepCurrent

	Slider slider2, win=JT_Controls, value=eventAmp, limits={spikeamp,0,0}
	SetDrawLayer /W=JT_Controls#embedwin /K UserFront
	SetDrawLayer /W=JT_Controls#embedwin UserFront
	SetDrawEnv /W=JT_Controls#embedwin xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
	DrawLine /W=JT_Controls#embedwin 0,eventAmp,1,eventAmp
	ControlUpdate /A /W=JT_Controls

End

////////////////////////////////////////////////////////////////////////////////////////////////////
// Load new Data Series folder (uses pulldown menu on panel)

// -------------------------------------------------------------------------------------------------
// Select_Series
// Panel popup callback for switching between loaded data series folders.
Function Select_Series(ctrlName, popNum, popStr)
	String ctrlName
	String popstr
	Variable popNum
	string inputwave
	string inputname
	string tempfolder1
	variable n

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder

	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	//change NVAR "tempfolder" to that selected by pulldown
	tempfolder = popStr

	If (cmpstr(data_type,"HEKA")==0)
		Load_HEKA_Wave ("LoadFolder",sweepCurrent)
	ElseIf (cmpstr(data_type,"SUTTER")==0)
		ReLoad_Sutter_Wave (popStr)
	ElseIf (cmpstr(data_type,"ABF")==0)
		Import_ABF_Data("LoadFolder")
	Else
		Abort "No data to load!"
	EndIf

End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// ReLoad_Sutter_Wave
// Reload an already-imported SutterPatch 2D wave into the panel state.
Function ReLoad_Sutter_Wave (ctrlName)
	String ctrlName

	String tempwave1
	string tempfolder1
	string tempfolder2
	Variable tempd
	variable n,i
	variable baseval
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	input_type = ""
	String currentDF = GetDataFolder(1)

	If (cmpstr(ctrlName,"Load")==0)
		String load_expmntfolder
		String load_seriesfolder
		Variable index=0

		//Part 1: find the series folder
		String seriesFolderlist = "root:"+data_type+":"
		String Foldername=""
		String ListofFolderNames=""
		do
			Foldername = GetIndexedObjName(seriesFolderlist,4,index)
			if (strlen(Foldername) == 0)
				break
			EndIf
			ListofFolderNames+=Foldername+";"
			index+=1
		while(1)

		Prompt load_seriesfolder, "Select series folder:", popup (ListofFolderNames)
		DoPrompt "Which folder to load?", load_seriesfolder

		If (V_flag!=0)
			Abort
		EndIf
		tempfilefolder = load_seriesfolder

		//Part 2: find the experiment folder
		String expmntFolderlist = "root:"+data_type+":"+load_seriesfolder
		Foldername=""
		ListofFolderNames=""
		index=0

		do
			Foldername = GetIndexedObjName(expmntFolderlist,4,index)
			if (strlen(Foldername) == 0)
				break
			EndIf
			ListofFolderNames+=Foldername+";"
			index+=1
		while(1)

		Prompt load_expmntfolder, "Select series folder:", popup (ListofFolderNames)
		DoPrompt "Which folder to load?", load_expmntfolder

		If (V_flag!=0)
			Abort
		EndIf
		tempfolder = load_expmntfolder


	Else

		tempfolder = ctrlName

	EndIf

	String seriesDataFolder = "root:"+data_type+":"+tempfilefolder+":"+tempfolder

	SetDataFolder $seriesDataFolder
	NVAR /Z sweepTime
	SVAR /Z FileNameTruncated

	tempwave = FileNameTruncated+input_type

	Wave twoDWave = $(seriesDataFolder+":"+tempwave)
	data_type = "SUTTER"
	sweepStartnum = 1
	sweepEndnum = (DimSize (twoDWave,1))
	sweepCurrent = sweepStartnum


	//If Baseline is checked then baseline subtract the wave
	controlInfo /W=JT_Controls check000
	Variable checknum = V_Value
	If  (checknum==1)
		For (i=0;i<sweepEndnum;i+=1)
			MatrixOP/FREE /O tempcol1 = col(twoDWave,i)
			baseval = mean (tempcol1)
			twoDWave[0, numpnts(tempcol1)-1][i]=tempcol1[p]-baseval
		EndFor
	EndIf

	//Find peak amplitude in a sample trace to pass to the Find Levels procedure
	MatrixOP/FREE firstcol = col(twoDWave, 0)
	SetScale /P x 0,DimDelta(twoDWave, 0 ),"s", firstcol

	Variable tempWavemin = waveMin(firstcol)
	wavestats /Q firstcol
	variable tempstatsvar1 = -10*V_adev //make signal detection negative and 2 times the background noise
	FindPeak /Q /B=1 /M=(tempstatsvar1) /N firstcol

	If (cmpstr(num2str(V_PeakVal),"NaN")==0)
		spikeamp = 10*tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = 100e-6
	ElseIf (V_PeakVal>(tempstatsvar1/8))
		spikeamp = 10*tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = V_PeakWidth
	Else
		spikeamp = tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = V_PeakWidth
	EndIf

	string popStrpath
	popStrpath = data_type+":"+tempfilefolder+":"+tempfolder
	UpdateControlPanel ("LoadSUTTERFolder",popStrpath,1)

	AppendToGraph /W=JT_Controls#embedwin $tempwave[][sweepCurrent-1]
	ModifyGraph /W=JT_Controls#embedwin rgb = (0,0,0)

	SetVariable setvar0, win=JT_Controls, value= spiketime
	SetVariable setvar1, win=JT_Controls, value= spikeamp
	SetVariable setvar2, win=JT_Controls, value= sweepStartnum
	SetVariable setvar3, win=JT_Controls, value= sweepEndnum
	SetVariable setvar4, win=JT_Controls, value= sweepCurrent
	Slider slider2, win=JT_Controls, value=eventAmp, limits={spikeamp,0,0}
	SetDrawLayer /W=JT_Controls#embedwin /K UserFront
	SetDrawLayer /W=JT_Controls#embedwin UserFront
	SetDrawEnv /W=JT_Controls#embedwin xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
	DrawLine /W=JT_Controls#embedwin 0,eventAmp,1,eventAmp
	ControlUpdate /A /W=JT_Controls


End
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// -------------------------------------------------------------------------------------------------
// Load_Sutter_Wave
// Load a SutterPatch 2D wave from a SutterPatch Data or Data:Analysis folder.
Function Load_Sutter_Wave (ctrlName): ButtonControl

	String ctrlName
	If (cmpstr(ctrlName,"Data")!=0)
		print "\r"+date()+": Import_Sutter_File function called at "+time()
	EndIf
	String tempwave1
	string tempfolder1
	string tempfolder2
	String load_folder
	String experiment_folder
	String analysis_folder
	String tempnameforfolder
	String sutterRoot

	Variable tempd
	variable n
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	NewDataFolder /O root:SUTTER
	input_type = ""

	String currentDF = GetDataFolder(1)

	//Load Button on File Tools tab
	If (cmpstr(ctrlName,"button008")==0)

		//Populate a list with any folders dragged from Browse Experiment
		String	rootDF = "root:"
		String	ListofFolderNames=""
		Variable index=0
		do
			String Foldername = GetIndexedObjName(rootDF,4,index)
			if (strlen(Foldername) == 0)
				break
			EndIf

			If (DataFolderExceptionCheck(Foldername))		//Packages and "A" does not need to be added to the list of folders for display
			
			//If file name begins with a number, the letter "x" will be appended to the beginning of it
				If (char2num(Foldername[0])<65)
					String OldFoldername = Foldername
					Foldername = "x"+Foldername
					RenameDataFolder root:$(OldFoldername), $(Foldername)
				EndIf		
				ListofFolderNames+=Foldername+";"
			EndIf
			index+=1
		while(1)

		Prompt experiment_folder, "SutterPatch file folder:", popup (ListofFolderNames)
		DoPrompt "Select SutterPatch file", experiment_folder

		If (V_flag!=0)
			Abort
		EndIf
		sutterRoot = "root:"+experiment_folder+":SutterPatch:"
		tempfilefolder = experiment_folder


		//"Load Series" button on Analysis Tools tab
	ElseIf (cmpstr(ctrlName,"button004")==0) //Load Series button
		sutterRoot = "root:"+tempfilefolder+":SutterPatch:"

		// PXP import button: the PXP has already been loaded into the current experiment.
		// Use the exact SutterPatch root found by Import_PXP_File so this also works
		// when the PXP preserves one nested top-level data folder.
	ElseIf (cmpstr(ctrlName,"LoadPXP")==0)
		SVAR /Z pxpSutterPatchRootMaybe = root:A:pxpSutterPatchRoot
		If (!SVAR_Exists(pxpSutterPatchRootMaybe))
			String /G root:A:pxpSutterPatchRoot = ""
		EndIf
		SVAR pxpSutterPatchRoot = root:A:pxpSutterPatchRoot
		If (strlen(pxpSutterPatchRoot) == 0)
			pxpSutterPatchRoot = JT_FindImportedSutterPatchRoot(tempfilefolder)
		EndIf
		If (strlen(pxpSutterPatchRoot) == 0)
			Abort "No SutterPatch:Data folder was found in the imported PXP folder."
		EndIf

		sutterRoot = pxpSutterPatchRoot
	EndIf

	// Choose which SutterPatch source folder to use. Data: is the common/default case.
	String sourceOptions = ""
	If (DataFolderExists(sutterRoot + "Data"))
		sourceOptions += "Data:;"
	EndIf
	If (DataFolderExists(sutterRoot + "Data:Analysis"))
		sourceOptions += "Data:Analysis:;"
	EndIf
	If (ItemsInList(sourceOptions) == 0)
		Abort "No SutterPatch Data: or Data:Analysis: folder was found at " + sutterRoot
	EndIf

	analysis_folder = "Data:"
	If (WhichListItem(analysis_folder, sourceOptions) < 0)
		analysis_folder = StringFromList(0, sourceOptions)
	EndIf
	load_folder = sutterRoot + analysis_folder
	Print "Using SutterPatch source folder: " + load_folder

	//Populate list with names of waves in data folder
	//String SourceDataFolder = load_folder
	String ListofWaveNames=""
	String tempwavename
	index=0
	Variable i, baseval
	do
		tempwavename = GetIndexedObjName(load_folder,1,index)
		if (strlen(tempwavename) == 0)
			break
		ElseIf (cmpstr(tempwavename,"ExperimentStructure")!=0)
			ListofWaveNames+=tempwavename+";"
		EndIf
		index+=1
	while(1)
	If (ItemsInList(ListofWaveNames) == 0)
		Abort "No SutterPatch waves were found in " + load_folder
	EndIf

	//Choose a Routine to load. The source popup defaults to Data:.
	Variable sourceChoice = WhichListItem(analysis_folder, sourceOptions) + 1
	If (sourceChoice < 1)
		sourceChoice = 1
	EndIf
	If (ItemsInList(sourceOptions) > 1)
		Prompt sourceChoice, "Source folder:", popup sourceOptions
		Prompt tempwave1, "Select Data routine:", popup (ListofWaveNames)
		DoPrompt "Load SutterPatch Data", sourceChoice, tempwave1
		If (V_flag != 0)
			SetDataFolder currentDF
			Abort "SutterPatch 2D wave not loaded!"
		EndIf

		String requestedSource = StringFromList(sourceChoice - 1, sourceOptions)
		If (cmpstr(requestedSource, analysis_folder) != 0)
			analysis_folder = requestedSource
			load_folder = sutterRoot + analysis_folder
			Print "Using SutterPatch source folder: " + load_folder

			ListofWaveNames = ""
			index = 0
			do
				tempwavename = GetIndexedObjName(load_folder,1,index)
				if (strlen(tempwavename) == 0)
					break
				ElseIf (cmpstr(tempwavename,"ExperimentStructure")!=0)
					ListofWaveNames+=tempwavename+";"
				EndIf
				index+=1
			while(1)
			If (ItemsInList(ListofWaveNames) == 0)
				SetDataFolder currentDF
				Abort "No SutterPatch waves were found in " + load_folder
			EndIf

			Prompt tempwave1, "Select " + analysis_folder + " routine:", popup (ListofWaveNames)
			DoPrompt "Load SutterPatch " + analysis_folder, tempwave1
			If (V_flag != 0)
				SetDataFolder currentDF
				Abort "SutterPatch 2D wave not loaded!"
			EndIf
		EndIf
	Else
		Prompt tempwave1, "Select wave", popup (ListofWaveNames)
		DoPrompt "Load SutterPatch Data", tempwave1
		If (V_flag != 0)
			SetDataFolder currentDF
			Abort "SutterPatch 2D wave not loaded!"
		EndIf
	EndIf

	If (V_flag==0)
		SetDataFolder $load_folder

		WAVE temp2Dwave = $(tempwave1)
		String SutterDataFolder = "root:SUTTER:"+tempfilefolder
		If (DataFolderExists(SutterDataFolder)!=1)
			NewDataFolder $SutterDataFolder
		EndIf

		tempfolder = NameofWave(temp2Dwave) //IgorInfo(1) puts filename as foldername

		String seriesDataFolder = SutterDataFolder+":"+tempfolder

		If (DataFolderExists(seriesDataFolder)!=1)
			NewDataFolder /S $seriesDataFolder
			Variable /G sweepTime //0 = absolute time
			String /G FileNameTruncated
		Else
			SetDataFolder $seriesDataFolder
			NVAR /Z sweepTime
			SVAR /Z FileNameTruncated
		EndIf

		String scanwaveName = NameofWave(temp2Dwave)
		Variable routine_num, series_num
		String stim_string,tempscan_string1

		tempscan_string1 = "R"+"%d%*[_]"+"S"+"%d%*[_]"+"%s"
		sscanf scanwaveName,tempscan_string1,routine_num,series_num,stim_string //at some point this info can be stored in the folder
		Variable valuesRead = V_flag
		if (valuesRead != 3)
			Printf "Error reading Wave name, got %d strings instead\r", valuesRead
			FileNameTruncated = scanwaveName
		Else
			FileNameTruncated = "R"+num2str(routine_num)+"S"+num2str(series_num)
		EndIf

		tempwave = FileNameTruncated+input_type

		Duplicate/O temp2Dwave,$(seriesDataFolder+":"+tempwave)
		Wave twoDWave = $(seriesDataFolder+":"+tempwave)
		data_type = "SUTTER"
		sweepStartnum = 1
		sweepEndnum = (DimSize (twoDWave,1))
		sweepCurrent = sweepStartnum


		//If Baseline is checked then baseline subtract the wave
		controlInfo /W=JT_Controls check000
		Variable checknum = V_Value
		If  (checknum==1)
			For (i=0;i<sweepEndnum;i+=1)
				MatrixOP/FREE /O tempcol1 = col(temp2Dwave,i)
				baseval = mean (tempcol1)
				twoDWave[0, numpnts(tempcol1)-1][i]=tempcol1[p]-baseval
			EndFor
		EndIf

		//Find peak amplitude in a sample trace to pass to the Find Levels procedure
		MatrixOP/FREE firstcol = col(twoDWave, 0)
		SetScale /P x 0,DimDelta(twoDWave, 0 ),"s", firstcol

		Variable tempWavemin = waveMin(firstcol)
		wavestats /Q firstcol
		variable tempstatsvar1 = -10*V_adev //make signal detection negative and 2 times the background noise
		FindPeak /Q /B=1 /M=(tempstatsvar1) /N firstcol

		If (cmpstr(num2str(V_PeakVal),"NaN")==0)
			spikeamp = 10*tempWavemin
			eventAmp = 0.65*spikeamp
			spiketime = 100e-6
		ElseIf (V_PeakVal>(tempstatsvar1/8))
			spikeamp = 10*tempWavemin
			eventAmp = 0.65*spikeamp
			spiketime = V_PeakWidth
		Else
			spikeamp = tempWavemin
			eventAmp = 0.65*spikeamp
			spiketime = V_PeakWidth
		EndIf

		string popStrpath
		popStrpath = "SUTTER:"+tempfilefolder+":"+tempfolder
		UpdateControlPanel ("LoadSUTTERFolder",popStrpath,1)

		AppendToGraph /W=JT_Controls#embedwin $tempwave[][sweepCurrent-1]
		ModifyGraph /W=JT_Controls#embedwin rgb = (0,0,0)

		SetVariable setvar0, win=JT_Controls, value= spiketime
		SetVariable setvar1, win=JT_Controls, value= spikeamp
		SetVariable setvar2, win=JT_Controls, value= sweepStartnum
		SetVariable setvar3, win=JT_Controls, value= sweepEndnum
		SetVariable setvar4, win=JT_Controls, value= sweepCurrent
		Slider slider2, win=JT_Controls, value=eventAmp, limits={spikeamp,0,0}
		SetDrawLayer /W=JT_Controls#embedwin /K UserFront
		SetDrawLayer /W=JT_Controls#embedwin UserFront
		SetDrawEnv /W=JT_Controls#embedwin xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
		DrawLine /W=JT_Controls#embedwin 0,eventAmp,1,eventAmp
		ControlUpdate /A /W=JT_Controls
	Else
		SetDataFolder currentDF
		Abort "SutterPatch 2D wave not loaded!"
	EndIf
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Load new Root folder (Sutter or HEKA/ABF)

// -------------------------------------------------------------------------------------------------
// Select_Folder
// Panel callback for switching the active root data type/folder: SUTTER, HEKA, or ABF.
Function Select_Folder(ctrlName): ButtonControl
	String ctrlName
	string inputwave
	string inputname
	string tempfolder1
	string tempfolder2
	string foldername
	String ListofFolderNames

	Variable tempd
	variable n, index
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent


	String	currentDF = "root:"
	//	String	ListofFolderNames=""
	//	Variable index=0
	//	do
	//		String Foldername = GetIndexedObjName(currentDF,4, index)
	//		if (strlen(Foldername) == 0)
	//			break
	//		EndIf
	//		If (DataFolderExceptionCheck(Foldername))		//Packages and "A" does not need to be added to the list of folders for display
	//			ListofFolderNames+=Foldername+";"
	//		EndIf
	//		index+=1
	//	while(1)

	Prompt tempfolder2, "Folder", popup ("SUTTER;HEKA;ABF")
	DoPrompt "Select New Folder", tempfolder2
	If (V_flag==0)

		//Switch to the requested data folder
		currentDF = "root:"+tempfolder2+":"

		If (DataFolderExists(currentDF)!=1)
			Abort "That Data Folder Doesn't Exist!"
		EndIf

		//If SutterPatch selected
		If (cmpstr(tempfolder2,"SUTTER")==0)
			data_type = "SUTTER"
			ReLoad_Sutter_Wave ("Load")

			//If HEKA selected
		ElseIf (cmpstr(tempfolder2,"HEKA")==0)
			ListofFolderNames=""
			index=0
			do
				Foldername = GetIndexedObjName(currentDF,4, index)
				if (strlen(Foldername) == 0)
					break
				EndIf
				ListofFolderNames+=Foldername+";"
				index+=1
			while(1)

			Prompt tempfolder1, "Series", popup (ListofFolderNames)
			Prompt tempd, "Select input# (e.g., 1 = I-mon)", popup ("1;2;3")
			DoPrompt "Select New Series", tempfolder1,tempd
			If (V_flag==0)
				data_type = "HEKA"
				tempfilefolder = tempfolder2
				tempfolder = tempfolder1
				SetDataFolder root:$(tempfilefolder):$(tempfolder)
				SVAR FileNameTruncated
				SVAR /Z input1_type
				SVAR /Z input2_type
				SVAR /Z input3_type
				SVAR /Z stim1_type
				SVAR /Z stim2_type
				SVAR /Z stim3_type

				NVAR /Z pptActTrace
				NVAR /Z pptActSweep
				NVAR /Z pptSweeps
				NVAR /Z sweepTime

				//Update gloabal variables in /A
				sweepStartnum = pptActSweep
				sweepEndnum = pptSweeps //could use DimSize of 2Dwave
				sweepCurrent = pptActSweep
				If ((tempd==1) && (SVAR_exists(input1_type)==1))
					input_type = input1_type
					stim_type = stim1_type
				ElseIf ((tempd==2) && (SVAR_exists(input2_type)==1))
					input_type= input2_type
					stim_type = stim2_type
				ElseIf ((tempd==3) && (SVAR_exists(input3_type)==1))
					input_type= input3_type
				EndIf

				tempwave = FileNameTruncated+input_type

				Load_HEKA_Wave ("LoadFolder",sweepCurrent)
			EndIf

			//If ABF selected
		ElseIf (cmpstr(tempfolder2,"ABF")==0)

			ListofFolderNames=""
			index=0
			do
				Foldername = GetIndexedObjName(currentDF,4, index)
				if (strlen(Foldername) == 0)
					break
				EndIf
				ListofFolderNames+=Foldername+";"
				index+=1
			while(1)

			Prompt tempfolder1, "Series", popup (ListofFolderNames)
			Prompt tempd, "Select input# (e.g., 1 = Input1)", popup ("1;2;3")
			DoPrompt "Select New Series", tempfolder1,tempd
			If (V_flag==0)
				tempfilefolder = tempfolder2
				tempfolder = tempfolder1
				data_type = "ABF"
				SetDataFolder root:$(tempfilefolder):$(tempfolder)
				SVAR FileNameTruncated
				SVAR /Z input1_type
				SVAR /Z input2_type
				SVAR /Z input3_type
				SVAR /Z stim1_type
				SVAR /Z stim2_type
				SVAR /Z stim3_type

				NVAR /Z ABFsweepStartnum
				NVAR /Z ABFsweepEndnum
				NVAR /Z ABFsweepCurrent

				//Update gloabal variables in /A
				sweepStartnum = ABFsweepStartnum
				sweepEndnum = ABFsweepEndnum //could use DimSize of 2Dwave
				sweepCurrent = ABFsweepCurrent
				If ((tempd==1) && (SVAR_exists(input1_type)==1))
					input_type = input1_type
					stim_type = stim1_type
				ElseIf ((tempd==2) && (SVAR_exists(input2_type)==1))
					input_type= input2_type
					stim_type = stim2_type
				ElseIf ((tempd==3) && (SVAR_exists(input3_type)==1))
					input_type= input3_type
				EndIf

				tempwave = FileNameTruncated+input_type

				Import_ABF_Data ("LoadFolder")
			EndIf
		EndIf
	EndIf

End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Select Wave to load

// -------------------------------------------------------------------------------------------------
// Select_Wave
// Load/select a wave from the current data folder or active zPhys data folder.
Function Select_Wave(ctrlName): ButtonControl
	String ctrlName
	string path
	string inputwave
	string inputname
	string popStrpath

	variable n, cTemp

	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave
	SVAR input_type = root:A:input_type
	SVAR stim_type = root:A:stim_type
	SVAR data_type = root:A:data_type

	NVAR spikeamp = root:A:spikeamp
	NVAR spiketime = root:A:spiketime
	NVAR eventAmp = root:A:eventamp
	NVAR sweepStartnum = root:A:sweepStartnum
	NVAR sweepEndnum = root:A:sweepEndnum
	NVAR sweepCurrent = root:A:sweepCurrent

	SVAR /Z FileNameTruncated
	SVAR /Z input1_type
	SVAR /Z input2_type
	SVAR /Z input3_type
	SVAR /Z stim1_type
	SVAR /Z stim2_type
	SVAR /Z stim3_type

	NVAR /Z pptActTrace
	NVAR /Z pptActSweep
	NVAR /Z pptSweeps
	NVAR /Z sweepTime

	String waveLoad
	String	tempfolder1 = GetDataFolder(0)
	String	tempfolder2 = GetDataFolder(1)
	String	tempstring1 = ParseFilePath (0,tempfolder2,":",0,2)
	String	tempstring2 = ParseFilePath (0,tempfolder2,":",0,1)

	String tempwavelist = WaveList("*", ";", "")

	If (cmpstr(tempwavelist,"")==0)
		Abort "No waves in folder!"

	Else

		If (cmpstr (tempfolder1, "root")==0)

			Prompt inputwave, "Select wave", popup WaveList("*", ";", "")
			DoPrompt "Load Wave", inputwave
			If (V_flag!=0)
				Abort
			Else
				tempwave = inputwave
				tempfolder = " "
				tempfilefolder = ""
				waveLoad = "LoadGeneric"
				popStrpath = ""
			EndIf

		ElseIf (cmpstr(tempstring2,"A")==0)

			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select wave", inputwave

			If (V_flag!=0)
				Abort
			Else
				tempwave = inputwave
				tempfolder = tempfolder1
				tempfilefolder = ParseFilePath (0,tempfolder2,":",0,1)
				popStrpath = tempfilefolder+":"+tempfolder
				waveLoad = "LoadGeneric"
			EndIf


		ElseIf (cmpstr(tempfolder,"Data")==0)

			Load_Sutter_Wave ("LoadWave")

		ElseIf (cmpstr(tempfolder,"Data")!=0)

			variable tempc = sweepStartnum
			variable tempd = pptActTrace

			Prompt tempc, "Sweep #:"
			Prompt tempd, "Input # (e.g., 1 = I-mon):", popup ("1;2;3")
			DoPrompt "Select Wave", tempc,tempd

			If (V_flag!=0)
				Abort "Canceled!"
			Else
				If ((tempd==1) && (SVAR_exists(input1_type)==1))
					input_type = input1_type
					stim_type = stim1_type
				ElseIf ((tempd==2) && (SVAR_exists(input2_type)==1))
					input_type= input2_type
					stim_type = stim2_type
				ElseIf ((tempd==3) && (SVAR_exists(input3_type)==1))
					input_type= input3_type
					stim_type = stim3_type
				Else
					Abort "No input "+num2str(tempd)+" in current folder!"
				EndIf

				If (cmpstr (tempfolder1, tempfolder)==0)	//changing wave within current file folder
					tempwave = FileNameTruncated+input_type

				ElseIf (cmpstr (tempstring2, "ABF")==0)
					tempwave = FileNameTruncated+"_"+num2str(sweepCurrent)
					tempfolder = tempfolder1
					tempfilefolder = ParseFilePath (0,tempfolder2,":",0,1)

				Else	//moving to new file folder
					tempwave = FileNameTruncated+input_type
					tempfolder = tempfolder1
					tempfilefolder = ParseFilePath (0,tempfolder2,":",0,1)
				EndIf
				Print "Loading wave..."
				sweepCurrent = tempc
				Load_HEKA_Wave ("LoadWave",sweepCurrent)

			EndIf
		Else
			Abort "Error!"		//time to fix this mess!
		EndIf

	EndIf

End

////////////////////////////////////////////////////////////////////////////////////////////////////
// Save Waves

// -------------------------------------------------------------------------------------------------
// save1
// Save an Igor binary wave (.ibw) to the Desktop path.
Function save1(ctrlName): ButtonControl
	String ctrlName
	string tempstring1
	string inputwave
	string tempsave
	SVAR tempwave = root:A:tempwave
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder
	//If tempwave comes from Analysis
	tempstring1 = ParseFilePath (0,tempwave,":",0,1)

	If (cmpstr (tempstring1, "A")==0)

		tempstring1 = ParseFilePath (0,tempwave,":",0,2)
		If (cmpstr (tempstring1, "Avg")==0)
			SetDataFolder root:A:Avg:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select Average wave", inputwave
		ElseIf (cmpstr (tempstring1, "Concat")==0)
			SetDataFolder root:A:Concat:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select Concat wave", inputwave
		ElseIf (cmpstr (tempstring1, "FFT1")==0)
			SetDataFolder root:A:FFT1:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select FFT wave", inputwave
		ElseIf (cmpstr (tempstring1, "Hist1")==0)
			SetDataFolder root:A:Hist1:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select Hist1 wave", inputwave
		ElseIf (cmpstr (tempstring1, "ISI")==0)
			SetDataFolder root:A:Concat:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select ISI wave", inputwave
		ElseIf (cmpstr (tempstring1, "V")==0)
			SetDataFolder root:A:V:
			Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
			DoPrompt "Select Vector wave", inputwave
		EndIf
		tempsave = inputwave+".ibw"
	Else
		SetDataFolder root:$(tempfilefolder):$(tempfolder)
		Prompt inputwave, "Input Wave", popup WaveList("*", ";", "")
		DoPrompt "Select wave", inputwave
		tempsave = inputwave+".ibw"
	EndIf
	If (V_flag==0)	//if cancel clicked on DoPrompt, then skip rest of proc
		//Save the inputwave
		Save /P=Desktop /C $inputwave as tempsave
		SetDataFolder tempfolder
	EndIf
End

//******************************************************************************************************
//******************************************************************************************************
//Michael Roberts' Axon Readin Code
// -------------------------------------------------------------------------------------------------
// Import_ABF_File
// Top-level ABF load callback: read the ABF header, then import the data.
Function Import_ABF_File(ctrlName):ButtonControl
	String ctrlName
	Variable StatusCheck=0
	String path

	print "\r"+date()+": Import_ABF_File function called at "+time()

	//Add functions so that data from one file is entered into folder named after that file
	StatusCheck = Read_ABF_Header("")
	If (StatusCheck == 0)
		Import_ABF_Data("")
	Else
		print "Error: ABF file not loaded."
	EndIf


End		//End of Import_ABF_File

//******************************************************************************************************
//******************************************************************************************************

// -------------------------------------------------------------------------------------------------
// Read_ABF_Header
// Read the ABF header into globals in root:ABF:<file> using fixed binary offsets.
Function Read_ABF_Header (tempFileSelection)			//This Function reads the header of an Axon ABF file and stores the information in global variables

	String tempFileSelection
	String CurrentDataFolder = GetDataFolder(1)

	SetDataFolder root:

	Variable refnum, i, tempvar1, tempvar2, tempvar3, j=0
	String message, tempstring1, tempstring2, tempstring3

	//Open the file to be loaded; prompt the user to select a file if tempFileSelection did not pass a file path to this function
	message = "Select an Axon *.abf file"
	If (strlen(tempFileSelection)==0)
		Open /R/D/T=".abf"/P=ABFPath/M=message refnum
		Open /R/Z refnum as S_filename
	Else
		Open /R/Z refnum as tempFileSelection
	EndIf
	If (V_flag!=0)		//Check to make sure that the user chose a file; if user hits cancel, the function quits here
		SetDataFolder CurrentDataFolder
		return -1		//Indicates failure
	EndIf
	tempFileSelection = S_fileName

	String tempPath = ParseFilePath (1,tempFileSelection,":",1,0)
	NewPath /O /Q ABFPath, tempPath


	print "Reading ABF file header..."

	//Create truncated File Name and temporarily hold it in tempstring1
	//If file name begins with a number, the letter "x" will be appended to the beginning of it
	//This avoids problems with displaying graphs and tables, the names of which cannot start with numbers
	tempstring1 = ParseFilePath (3,tempFileSelection,":",0,0)
	If (char2num(tempstring1[0])<65)
		tempstring1[0]="x"
	EndIf

	NewDataFolder /O root:ABF
	NewDataFolder /O/S root:ABF:$tempstring1					//Create data folder named after truncated file name to hold all waves and variables associated with the selected file

	String /G FileName = ParseFilePath (0,tempFileSelection,":",1,0)				//Global string containing file name of selected file
	String /G FileNameTruncated = tempstring1			//Global string containing file name of selected file minus ".abf"
	String /G FileSelection = tempFileSelection		//Global string containing path to selected file + file name
	String /G data_type = "ABF"

	Variable /G nOperationMode		//Global variable containing the recording mode, i.e. gapfree, episodic, etc.
	Variable /G lActualAcqLength		//Global variable containing the total number of ADC samples in the data file
	Variable /G lActualEpisodes		//Global variable contiaining the number of sweeps in the file
	Variable /G lFileStartDate			//Global variable containing the date the data was collected in YYMMDD format
	Variable /G lFileStartTime			//Global variable containing the time past midnight in seconds when the data collection started
	String /G sFileStartDate, sFileStartDateYear, sFileStartDateMonth, sFileStartDateDay	//Global strings containing date information for when data was acquired
	String /G sFileStartTime			//Global string containing time that data collection started
	Variable /G lStopwatchTime		//Global variable containing time (in sec) on stopwatch when recording started
	String /G sStopwatchTime			//Global string containing formatted time on stopwatch when recording started
	Variable /G lDataSectionPtr		//Global variable containing block number of start of data section in abf file
	Variable /G lScopeConfigPtr		//Global variable containing block number of start of ABF Scope Config section;
	//note that this value = 0 when dealing with an ABF file that was exported from Clampfit;
	//such files do not require scaling of the data by the YScaleFactor
	Variable /G nDataFormat			//Global variable containing value indicating data format where 0 = 2-byte integer and 1 = IEEE 4 byte float
	Variable /G nADCnumChannels	//Global variable containing the number of analog input channels that were recorded
	Variable /G fADCSampleInterval	//Global variable containing the interval between multiplexed a/d samples in microsec (us) - to get sampling rate multiply times number of channels sampled
	Variable /G lNumSamplesPerEpisode	//Global variable containing the number of samples per sweep; pertains only to files containing sweeps
	Variable /G fEpisodeStartToStart	//Global variable containing the time in seconds from sweep start to sweep start
	Variable /G fADCRange			//Global variable containing the ADC positive full scale input in Volts
	Variable /G lADCResolution		//Global variable containing the number of ADC counts that equal fADCRange
	Variable /G DataSamplingInt		//Global variable containing the inverse of the sampling frequency in units of microsec

	FSetPos refnum,8
	FBinRead /F=2 refnum, nOperationMode

	FSetPos refnum,10
	FBinRead /F=3 refnum, lActualAcqLength

	FSetPos refnum,16
	FBinRead /F=3 refnum, lActualEpisodes

	FSetPos refnum, 20
	FBinRead /F=3 refnum, lFileStartDate
	sFileStartDate = num2istr(lFileStartDate)
	sFileStartDateYear = sFileStartDate[0,3]
	sFileStartDateMonth = sFileStartDate[4,5]
	sFileStartDateDay = sFileStartDate[6,7]
	sFileStartDate = sFileStartDateMonth+"-"+sFileStartDateDay+"-"+sFileStartDateYear

	FSetPos refnum, 24
	FBinRead /F=3 refnum, lFileStartTime
	tempvar1 = floor(lFileStartTime/3600)
	tempvar2 = floor(((lFileStartTime/3600)-tempvar1)*60)
	tempvar3 = ((((lFileStartTime/3600)-tempvar1)*60)-tempvar2)*60
	tempstring1 = num2str(tempvar1)
	If (tempvar1<10)						//If statements correct for times less than 10 showing up as 3:2:7 when should be 03:02:07
		tempstring1="0"+tempstring1
	EndIf
	tempstring2 = num2str(tempvar2)
	If (tempvar2<10)
		tempstring2="0"+tempstring2
	EndIf
	tempstring3 = num2str(tempvar3)
	If (tempvar3<10)
		tempstring3="0"+tempstring3
	EndIf
	sFileStartTime = tempstring1+":"+tempstring2+":"+tempstring3

	FSetPos refnum, 28
	FBinRead /F=3 refnum, lStopWatchTime
	tempstring2=num2str((lStopwatchTime/60-floor(lStopwatchTime/60))*60)
	If ((lStopwatchTime/60-floor(lStopwatchTime/60))*60<10)
		tempstring2="0"+tempstring2
	EndIf
	sStopwatchTime = num2str(floor(lStopwatchTime/60))+":"+tempstring2

	FSetPos refnum, 40
	FBinRead /F=3 refnum, lDataSectionPtr

	FSetPos refnum, 52
	FBinRead /F=3 refnum, lScopeConfigPtr

	FSetPos refnum, 100
	FBinRead /F=2 refnum, nDataFormat

	FSetPos refnum, 120
	FBinRead /F=2 refnum, nADCnumChannels

	FSetPos refnum, 122
	FBinRead /F=4 refnum, fADCSampleInterval

	FSetPos refnum, 138
	FBinRead /F=3 refnum, lNumSamplesPerEpisode

	FSetPos refnum, 178
	FBinRead /F=4 refnum, fEpisodeStartToStart

	FSetPos refnum, 244
	FBinRead /F=4 refnum, fADCRange

	FSetPos refnum, 252
	FBinRead /F=3 refnum, lADCResolution

	For (i=1; i<=nADCnumChannels; i+=1)
		tempvar1=0
		tempstring1 = ""

		For (j=0; j<10; j+=1)
			FSetPos refnum, (442+j+(i*10))
			FBinRead /F=1 refnum, tempvar1
			tempstring1 += num2char(tempvar1)
		EndFor

		tempstring2 = "input"+num2str(i)+"name"
		String /G $tempstring2 = tempstring1
		String /G $("input"+num2str(i)+"_type")= "_input"+num2str(i)//need to add something here
		String /G $("stim"+num2str(i)+"_type") = "_stim"+num2str(i)//need to add something here
	EndFor

	For (i=1; i<=nADCnumChannels; i+=1)
		tempvar1=0
		tempstring1 = ""

		For (j=0; j<8; j+=1)
			FSetPos refnum, (602+j+(i*8))
			FBinRead /F=1 refnum, tempvar1
			tempstring1 += num2char(tempvar1)
		EndFor

		tempstring2 = "input"+num2str(i)+"units"
		String /G $tempstring2 = tempstring1
	EndFor




	For (i=1; i<=nADCnumChannels; i+=1)
		FSetPos refnum, (922+(i*4))
		FBinRead /F=4 refnum, tempvar1
		tempstring1 = "fInstrumentScaleFactorCh"+num2str(i)
		Variable /G $tempstring1 = tempvar1	//Creates global variable to hold the ADC scale factors
	EndFor

	//Will assume that telegraphing was enabled for data acquisition; can add a check for this by looking at byte offset 4512

	For (i=1; i<=nADCnumChannels; i+=1)
		FSetPos refnum, (4576+(i*4))
		FBinRead /F=4 refnum, tempvar1
		tempstring1 = "fTelegraphAdditGainCh"+num2str(i)
		Variable /G $tempstring1 = tempvar1		//Creates global variables to hold the additional gain values
	EndFor

	For (i=1; i<=nADCnumChannels; i+=1)
		FSetPos refnum, (4640+(i*4))
		FBinRead /F=4 refnum, tempvar1
		tempstring1 = "fTelegraphFilterCh"+num2str(i)
		Variable /G $tempstring1 = tempvar1		//Creates global variables to hold the lowpass filter values
	EndFor

	//Calculate Y scale conversion factor for each input channel
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "YScaleFactorCh"+num2str(i)
		tempstring2 = "fInstrumentScaleFactorCh"+num2str(i)
		tempstring3 = "fTelegraphAdditGainCh"+num2str(i)
		NVAR InstrumentScaleFactor = $tempstring2
		NVAR TelegraphAdditGain = $tempstring3
		Variable /G $tempstring1 = (lADCResolution/fADCRange)*InstrumentScaleFactor*TelegraphAdditGain
	EndFor

	DataSamplingInt = (fADCSampleInterval*nADCnumChannels)/1000000

	Variable /G CursorPairsNum = 1		//CursorPairsNum and PrevCursorPairsNum keep track of how many cursors to show on the graph for the imported data
	Variable /G PrevCursorPairsNum = 0
	Variable /G SweepToHighlight = 1
	Variable /G SweepToggleSwitch = 1
	String /G SetPolarityStr = "0"
	SVAR SetPolarityStr = SetPolarityStr
	For (i=0; i<nADCnumChannels; i+=1)
		SetPolarityStr +="0"
	EndFor


	//Readout of parameters and variables loaded from header
	Print "FileSelection is "+FileSelection
	Print "Data was acquired on "+sFileStartDateMonth+"-"+sFileStartDateDay+"-"+sFileStartDateYear+" at (hh:mm:ss) "+sFileStartTime
	Print "Stopwatch Time (mm:ss) = "+sStopwatchTime
	Print "nOperationMode = "+num2str(nOperationMode)
	Print "lActualAcqLength = "+num2str(lActualAcqLength)
	Print "IActualEpisodes = "+num2str(lActualEpisodes)
	Print "lDataSectionPtr = "+num2str(lDataSectionPtr)
	Print "nDataFormat = "+num2str(nDataFormat)
	Print "nADCnumChannels = "+num2str(nADCnumChannels)
	Print "fADCSampleInterval = "+num2str(fADCSampleInterval)
	Print "lNumSamplesPerEpisode = "+num2str(lNumSamplesPerEpisode)
	Print "fEpisodeStartToStart = "+num2str(fEpisodeStartToStart)
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "input"+num2str(i)+"name"
		SVAR tempstring4 = $tempstring1
		print "Name of Input "+num2str(i)+" is: "+tempstring4
	EndFor
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "input"+num2str(i)+"units"
		SVAR tempstring4 = $tempstring1
		print "Units for Input "+num2str(i)+" are: "+tempstring4
	EndFor
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "fInstrumentScaleFactorCh"+num2str(i)
		NVAR tempvar4 = $tempstring1
		print "ADC scale factor for Ch"+num2str(i)+" is: "+num2str(tempvar4)
	EndFor
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "fTelegraphAdditGainCh"+num2str(i)
		NVAR tempvar4 = $tempstring1
		print "Additional Gain for Input "+num2str(i)+" is: "+num2str(tempvar4)+"x"
	EndFor
	For (i=1; i<=nADCnumChannels; i+=1)
		tempstring1 = "fTelegraphFilterCh"+num2str(i)
		NVAR tempvar4 = $tempstring1
		print "Lowpass filter for Input "+num2str(i)+" is: "+num2str(tempvar4)+" Hz"
	EndFor


	Close refnum

	print "Finished reading header."

	return 0		//Signifies success

End		//End of Read_ABF_Header

//******************************************************************************************************
//******************************************************************************************************

// -------------------------------------------------------------------------------------------------
// Import_ABF_Data
// Import ABF episodic or gap-free data into per-input 2D waves and refresh the panel display.
Function Import_ABF_Data(tempFileSelection)
	String tempFileSelection
	NVAR lDataSectionPtr, lNumSamplesPerEpisode, nADCnumChannels, lActualAcqLength, nDataFormat, lActualEpisodes
	NVAR DataSamplingInt, nOperationMode, lScopeConfigPtr
	SVAR FileSelection
	SVAR FileNameTruncated

	String XScaleWaveUnits
	String datatypeStr
	Variable i, j, k, n, tempvar1, ivar, jvar
	Variable tempd = 1
	Variable tempsweepStartnum = 1
	Variable tempsweepEndnum = 1
	Variable checknum = 0
	Variable baseval = 0
	String tempstring1, tempstring2, tempstring3

	If (nOperationMode==5)
		datatypeStr = "episodic"
	ElseIf (nOperationMode==3)
		datatypeStr = "gap-free"
	EndIf

	print "Loading "+datatypeStr+" data from "+num2str(nADCnumChannels)+" input channels in "+FileSelection

	//Load data from ABF file according to whether or not it is in short integer of floating format
	Make /O/N=(lActualAcqLength) TempWave0 //Make a wave to store GBLoadwave Data

	If (nDataFormat==0)
		GBLoadWave /O/B/Q/N=TempWave/T={16,2}/S=(512*lDataSectionPtr) FileSelection
	ElseIf (nDataFormat==1)
		GBLoadWave /O/B/Q/N=TempWave/T={2,2}/S=(512*lDataSectionPtr) FileSelection
	Else
		Print "Error reading data format."
		Return 0
	EndIf


	If (nOperationMode==5)		//Import depends on acquisition mode; mode 5 is Episodic so import will assume multiple sweeps (but should work for just one sweep)

		print "There are "+num2str(lActualEpisodes)+" sweeps in each channel."

		Make /O/N=(lNumSamplesPerEpisode/nADCnumChannels) tempwaveX
		Wave tempwaveX


		//JT ADDED SWEEP SELECTION

		tempsweepStartnum = 1
		tempsweepEndnum = lActualEpisodes
		tempd = 1

		//Prompt tempa, "Group # (E-1):"
		Prompt tempsweepStartnum, "Start wave:"
		Prompt tempsweepEndnum, "End wave:"
		Prompt tempd, "Display which input", popup "Input1;Input2;Input3;all"
		DoPrompt "Load ABF File", tempsweepStartnum,tempsweepEndnum, tempd
		If (V_flag!=0)	//if cancel clicked on DoPrompt, then skip rest of proc
			Abort
		EndIf
		SVAR /Z tempwave = root:A:tempwave
		SVAR /Z tempfolder = root:A:tempfolder
		SVAR /Z tempfilefolder = root:A:tempfilefolder
		SVAR /Z input_type = root:A:input_type
		SVAR /Z stim_type = root:A:stim_type
		SVAR /Z data_type = root:A:data_type
		SVAR /Z input1_type
		SVAR /Z input2_type
		SVAR /Z input3_type
		SVAR /Z stim1_type
		SVAR /Z stim2_type
		SVAR /Z stim3_type
		NVAR /Z spikeamp = root:A:spikeamp
		NVAR /Z spiketime = root:A:spiketime
		NVAR /Z eventAmp = root:A:eventamp
		NVAR sweepStartnum = root:A:sweepStartnum
		NVAR sweepEndnum = root:A:sweepEndnum
		NVAR sweepCurrent = root:A:sweepCurrent
		Variable /G ABFsweepStartnum
		Variable /G  ABFsweepCurrent
		Variable /G ABFsweepEndnum
		Variable /G d
		Variable /G f=1 //start time is 0 -- Concat is forced over Stitch (see Concat function)
		ABFsweepStartnum = tempsweepStartnum
		ABFsweepCurrent = ABFsweepStartnum
		If (tempsweepEndnum > lActualEpisodes)
			tempsweepEndnum = lActualEpisodes
		EndIf
		ABFsweepEndnum = tempsweepEndnum
		d = tempd
		If (d == 1)
			input_type = input1_type
		ElseIf (d == 2)
			input_type = input2_type
		ElseIf (d == 3)
			input_type = input3_type
		Else
			input_type = input1_type		// "all" loads all inputs; display input 1 by default.
		EndIf

		// JT added -- Display panel to indicate data is loading.
		NewPanel /N=FileLoadWin /FLT=2 /W=(800,400,1000,450) as "Loading..."
		ModifyPanel cbRGB=(30583,30583,30583), frameStyle=1, NoEdit=1
		DrawText 21,20,"Please wait.."
		SetActiveSubwindow _endfloat_
		DoUpdate

		For (i=(tempsweepStartnum-1); i<tempsweepEndnum; i+=1)		//Nested loops to deconvolute data and sort it into waves by input channel and sweep
			ivar = i*lNumSamplesPerEpisode

			For (j=1; j<=nADCnumChannels; j+=1)//JT adjusted "For" loop for multiple ADC channels with "break" below

				tempwaveX=NAN
				jvar = ivar+j

				For (k=0; k<(lNumSamplesPerEpisode/nADCnumChannels); k+=1)
					tempvar1 = Tempwave0[jvar+nADCnumChannels*k]
					tempwaveX[k] = tempvar1
				EndFor


				tempstring1 = "YScaleFactorCh"+num2str(j)		//Calls up Y scale factor so that waves can be stored already scaled
				NVAR tempscalefactor = $tempstring1
				tempstring2 = FileNameTruncated+"_"+num2str(i+1)+"_input"+num2str(j)


				//lScopeConfigPtr = 0 means that file was extracted from an original recording file in Clampfit
				//and the data values should already be appropriately scaled in the Y-axis
				//If (lScopeConfigPtr != 0)
				Make /O/N=(lNumSamplesPerEpisode/nADCnumChannels) $tempstring2 = (tempwaveX/(tempscalefactor*1000)) //'*1000 to adjust to A from mA //*5000000 scaled for brownlee
				//Else
				//Make /O/N=(lNumSamplesPerEpisode/nADCnumChannels) $tempstring2 = (tempwaveX)
				//EndIf
				SetScale/P x 0,(DataSamplingInt),"s", $tempstring2

				If (j==tempd)
					break //JT added - inputs 1-3
				EndIf
			EndFor

			//JT ----Determine if Baseline is checked
			WAVE wave1 = $tempstring2
			controlInfo /W=JT_Controls check000
			checknum = V_Value
			If  (checknum==1)  //If Baseline is checked then baseline subtract the waves
				baseval = mean(wave1, 0, 0.1)
				wave1 = (wave1-baseval)
			EndIf

		EndFor

		//Create X (time) scale for Episodic waves
		Make /O/N=(lNumSamplesPerEpisode/nADCnumChannels) XScaleWave
		For (i=0; i<(lNumSamplesPerEpisode/nADCnumChannels); i+=1)
			XScaleWave[i] = i*DataSamplingInt
		EndFor
		XScaleWaveUnits = "s"



	ElseIf (nOperationMode==3)	//Mode 3 is GapFree; Gap-free data is stored as a number of episodes(sweeps) and the following code should bring them together into one wave

		SVAR tempwave = root:A:tempwave
		SVAR tempfolder = root:A:tempfolder
		SVAR tempfilefolder = root:A:tempfilefolder
		SVAR input_type = root:A:input_type
		SVAR stim_type = root:A:stim_type
		SVAR data_type = root:A:data_type
		SVAR input1_type
		SVAR input2_type
		SVAR input3_type
		SVAR stim1_type
		SVAR stim2_type
		SVAR stim3_type
		NVAR spikeamp = root:A:spikeamp
		NVAR spiketime = root:A:spiketime
		NVAR eventAmp = root:A:eventamp

		NVAR sweepStartnum = root:A:sweepStartnum
		NVAR sweepEndnum = root:A:sweepEndnum
		NVAR sweepCurrent = root:A:sweepCurrent


		Variable /G ABFsweepStartnum
		Variable /G  ABFsweepCurrent
		Variable /G ABFsweepEndnum
		Variable /G d
		Variable /G f=1 //start time is 0 -- Concat is forced over Stitch (see Concat function)

		tempsweepStartnum = 1
		tempsweepEndnum = 1
		tempd = 1
		ABFsweepStartnum = 1
		ABFsweepCurrent = ABFsweepStartnum
		ABFsweepEndnum = 1

		Prompt tempd, "Display which input", popup "Input1;Input2;Input3;all"
		DoPrompt "Load ABF File", tempd
		If (V_flag==1)	//if cancel clicked on DoPrompt, then skip rest of proc
			abort
		EndIf

		If (tempd == 1)
			d = 1
			input_type = input1_type
		ElseIf (tempd == 2)
			d = 2
			input_type = input2_type
		ElseIf (tempd == 3)
			d = 3
			input_type = input3_type
		Else
			d = 4
			input_type = input1_type		// "all" loads all inputs; display input 1 by default.
		EndIf


		// JT added -- Display panel to indicate data is loading.
		NewPanel /N=FileLoadWin /FLT=2 /W=(800,400,1000,450) as "Loading..."
		ModifyPanel cbRGB=(30583,30583,30583), frameStyle=1, NoEdit=1
		DrawText 21,20,"Please wait.."
		SetActiveSubwindow _endfloat_
		DoUpdate

		Make /O/N=(lActualAcqLength/nADCnumChannels) tempwaveX
		Wave tempwaveX

		For (i=0; i<nADCnumChannels; i+=1)		//Nested loops to deconvolute data and sort it into waves by input channel

			tempwaveX=NAN

			For (k=0; k<(lActualAcqLength/nADCnumChannels); k+=1)
				tempvar1 = Tempwave0[i+nADCnumChannels*k]
				tempwaveX[k] = tempvar1
			EndFor

			tempstring1 = "YScaleFactorCh"+num2str(i+1)		//Calls up Y scale factor so that waves can be stored already scaled
			NVAR tempscalefactor = $tempstring1
			tempstring2 = FileNameTruncated+"_"+num2str(ABFsweepCurrent)+"_input"+num2str(i+1)

			//lScopeConfigPtr = 0 means that file was extracted from an original recording file in Clampfit
			//and the data values should already be appropriately scaled in the Y-axis
			If (lScopeConfigPtr != 0)
				Make /O/N=(lActualAcqLength/nADCnumChannels) $tempstring2 = (tempwaveX/tempscalefactor)
			Else
				Make /O/N=(lActualAcqLength/nADCnumChannels) $tempstring2 = (tempwaveX/tempscalefactor)
			EndIf
			SetScale/P x 0,(DataSamplingInt),"s", $tempstring2

			//Baseline subtract by fitting a line to the wave and subtracting it...
			controlInfo /W=JT_Controls check000
			checknum = V_Value
			If  (checknum==1)  //If Baseline is checked then baseline subtract the waves
				WAVE wave1 = $tempstring2
				CurveFit/L=(numpnts($tempstring2)) /M=2 /Q /W=0 line, $tempstring2 /D
				String fitwavename = "fit_"+tempstring2
				WAVE fitwave = $fitwavename
				wave1 = (wave1-fitwave)
				print "Channel "+num2str(i+1)+" data imported AND BASELINE SUBTRACTED!!"
			Else
				print "Channel "+num2str(i+1)+" data imported"
			EndIf

			If ((i + 1) == tempd)
				break		// Selected one input; do not continue to later channels.
			EndIf
		EndFor

		//Create X (time) scale for Gap-Free waves
		Make /O/N=(lActualAcqLength/nADCnumChannels) XScaleWave
		For (i=0; i<(lActualAcqLength/nADCnumChannels); i+=1)
			XScaleWave[i] = i*DataSamplingInt
		EndFor
		XScaleWaveUnits = "ms"

		lActualEpisodes = 1	//Gap-Free data has only one sweep
		lNumSamplesPerEpisode = lActualAcqLength

	Else	//Other Modes, 1=Event-Driven, 2=Oscilloscope, loss free, 4=Oscilloscope, high speed;  These are not supported because who the hell uses them?
		print "Acquisition modes 1, 2, and 4 are not currently supported."
		Return 0
	EndIf


	//Create a 2D wave to store all loaded sweeps from the series
	string temp2Dwave
	String tempstring2D1

	For (j=1; j<=nADCnumChannels; j+=1)

		If (j==1)

			For (i=tempsweepStartnum; i<=tempsweepEndnum; i+=1)
				temp2Dwave = FileNameTruncated+"_"+num2str(i)+input1_type

				wave wave1 = $(temp2Dwave)

				If (i==tempsweepStartnum)
					tempstring2D1 = FileNameTruncated+input1_type
					Duplicate /O wave1 $tempstring2D1
					Wave wave2D1 = $(tempstring2D1)
					Redimension /N=(-1, tempsweepEndnum) wave2D1
					wave2D1 = NaN
					wave2D1[][i-1] = wave1[p]

				Else	//Add subsequent waves to 2D wave
					wave2D1[][i-1] = wave1[p]

				EndIf
				KillWaves wave1
			EndFor
			If (j==tempd)
				break //JT added - inputs 1-3
			EndIf
		ElseIf (j==2)

			For (i=tempsweepStartnum; i<=tempsweepEndnum; i+=1)
				temp2Dwave = FileNameTruncated+"_"+num2str(i)+input2_type

				wave wave1 = $(temp2Dwave)

				If (i==tempsweepStartnum)
					tempstring2D1 = FileNameTruncated+input2_type
					Duplicate /O wave1 $tempstring2D1
					Wave wave2D1 = $(tempstring2D1)
					Redimension /N=(-1, tempsweepEndnum) wave2D1
					wave2D1 = NaN
					wave2D1[][i-1] = wave1[p]

				Else	//Add subsequent waves to 2D wave
					wave2D1[][i-1] = wave1[p]

				EndIf
				KillWaves wave1
			EndFor

			If (j==tempd)
				break //JT added - inputs 1-3
			EndIf
		ElseIf (j==3)

			For (i=tempsweepStartnum; i<=tempsweepEndnum; i+=1)
				temp2Dwave = FileNameTruncated+"_"+num2str(i)+input3_type

				wave wave1 = $(temp2Dwave)

				If (i==tempsweepStartnum)
					tempstring2D1 = FileNameTruncated+input3_type
					Duplicate /O wave1 $tempstring2D1
					Wave wave2D1 = $(tempstring2D1)
					Redimension /N=(-1, tempsweepEndnum) wave2D1
					wave2D1 = NaN
					wave2D1[][i-1] = wave1[p]

				Else	//Add subsequent waves to 2D wave
					wave2D1[][i-1] = wave1[p]

				EndIf
				KillWaves wave1
			EndFor


		EndIf
	EndFor //end scan through available ADC channels

	//JT added strings and stuff
	tempwave = FileNameTruncated+input_type
	tempfilefolder = "ABF"
	tempfolder = GetDataFolder(0)
	data_type = "ABF"
	sweepStartnum = ABFsweepStartnum
	sweepEndnum = ABFsweepEndnum
	sweepCurrent = ABFsweepCurrent


	//Find peak amplitude in a sample trace to pass to the Find Levels procedure
	MatrixOP/FREE firstcol = col(wave2D1, 0)
	SetScale /P x 0,DimDelta(wave2D1, 0 ),"s", firstcol

	Variable tempWavemin = waveMin(firstcol)
	wavestats /Q firstcol
	variable tempstatsvar1 = -10*V_adev //make signal detection negative and 2 times the background noise
	FindPeak /Q /B=1 /M=(tempstatsvar1) /N firstcol

	If (cmpstr(num2str(V_PeakVal),"NaN")==0)
		spikeamp = 10*tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = 100e-6
	ElseIf (V_PeakVal>(tempstatsvar1/8))
		spikeamp = 10*tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = V_PeakWidth
	Else
		spikeamp = tempWavemin
		eventAmp = 0.65*spikeamp
		spiketime = V_PeakWidth
	EndIf


	KillWindow /Z FileLoadWin			// Kill panel

	String popStrpath = tempfilefolder+":"+tempfolder
	UpdateControlPanel ("Import_ABF_File", popStrpath,1)
	Print sweepCurrent
	AppendToGraph /W=JT_Controls#embedwin $tempwave[][sweepCurrent-1] //Wave0 ==sweep 1
	ModifyGraph /W=JT_Controls#embedwin rgb = (0,0,0)

	SetVariable setvar0, win=JT_Controls, value= spiketime
	SetVariable setvar1, win=JT_Controls, value= spikeamp
	SetVariable setvar2, win=JT_Controls, value= sweepStartnum
	SetVariable setvar3, win=JT_Controls, value= sweepEndnum
	SetVariable setvar4, win=JT_Controls, value= sweepCurrent

	Slider slider2, win=JT_Controls, value=eventAmp, limits={spikeamp,0,0}
	SetDrawLayer /W=JT_Controls#embedwin /K UserFront
	SetDrawLayer /W=JT_Controls#embedwin UserFront
	SetDrawEnv /W=JT_Controls#embedwin xcoord= rel,ycoord= left, linefgc= (65535,0,0), dash=1
	DrawLine /W=JT_Controls#embedwin 0,eventAmp,1,eventAmp
	ControlUpdate /A /W=JT_Controls

	//End of JT additions

	Print "ABF data import complete."
	KillWaves /Z Tempwave0, TempwaveX

End		//End of  Import_ABF_Data ()

//******************************************************************************************************
//******************************************************************************************************
