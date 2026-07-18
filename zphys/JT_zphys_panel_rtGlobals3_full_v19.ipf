#pragma rtGlobals=3        // Full Igor Pro 9 cleanup version.
#pragma IgorVersion = 9.0    // Target Igor Pro 9 on macOS.
#include <Scatter Dot Plot>

// =================================================================================================
// JT_zphys_panel.ipf
// Main zPhys control panel for electrophysiology analysis.
//
// Full rtGlobals=3 cleanup pass: keeps existing function/control names and external callback names,
// adds documentation, fixes the Function/End mismatch, improves UI labels/sizes, and makes
// Analysis Tools settings buttons deterministic on Igor Pro 9/macOS; v13 uses an independent settings panel to avoid hosted-panel focus/click capture on Igor Pro 9/macOS; v14 fixes independent-panel creation and reorganizes File Tools for Sutter PXP-first workflow; v15 renames the settings window to zPhys_Settings to avoid colliding with the JT_Settings/JT_settings user function namespace; v16 fixes popupmenu1 commands so the main series popup is always targeted to JT_Controls and is not accidentally created in the settings panel; v17 keeps the independent settings panel anchored beside JT_Controls when it is opened or when tabs/pages switch.
// =================================================================================================

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

Menu " <}}}>< "

	"zPhys Panel", Start_A(0)
	"Reload zPhys Panel", Start_A(1)
	
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Keep the independent zPhys settings panel visually anchored to JT_Controls.
// This is used instead of a hosted subpanel because hosted panels captured clicks
// from the main Analysis Tools buttons on Igor Pro 9/macOS.
Function zPhys_PositionSettingsPanel()

	DoWindow JT_Controls
	If (V_flag==0)
		Return 0
	Endif

	DoWindow zPhys_Settings
	If (V_flag==0)
		Return 0
	Endif

	GetWindow JT_Controls wsize
	Variable panelLeft = V_left
	Variable panelTop = V_top
	Variable panelRight = V_right
	Variable settingsLeft = panelLeft - 135
	Variable settingsTop = panelTop + 130

	// If there is no room on the left edge of the screen, place the settings
	// panel just to the right of JT_Controls instead.
	If (settingsLeft < 5)
		settingsLeft = panelRight + 5
	Endif

	MoveWindow /W=zPhys_Settings settingsLeft, settingsTop, settingsLeft+130, settingsTop+425
	Return 1
End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Build the context-sensitive settings panel for Concatenate, Analysis, or Find Spikes.
Function JT_settings(ctrlName) : ButtonControl
	String ctrlName
	Variable bx=10
	Variable by=10
	
	// Rebuild this independent settings panel deterministically.  This version avoids the hosted JT_Controls#JT_Settings panel, which could capture clicks on macOS.
	// It rebuilds a separate zPhys_Settings panel and leaves the main Analysis Tools buttons clickable.
	// That could briefly disable/hide the same category button that was being clicked,
	// making Concat/Analysis/Find Spikes feel like they needed multiple clicks.
	DoWindow /F JT_Controls
	If (V_flag==0)
		Abort "JT_Controls is not open. Run Start_A(0) first."
	Endif
	KillWindow /Z zPhys_Settings
	DoUpdate
	
	// Create near JT_Controls, then immediately run the shared anchor routine.
	// The temporary coordinates are overwritten by zPhys_PositionSettingsPanel().
	NewPanel /W=(50,50,180,475) /K=1 as "zPhys Settings"
	DoWindow /C zPhys_Settings
	ModifyPanel frameStyle=1, noEdit=1, fixedSize=1
	zPhys_PositionSettingsPanel()
	
	If (cmpstr(ctrlName,"button108")==0) // Find Spikes settings
		//Button button0,pos={32,30},size={150,20},proc=Find_StimPeaks,title="Find Stim events"
		Variable by1 = 140
		Button button108a, pos={bx,by1}, size={100,15}, title="Find Spikes", proc=Find_Peaks,  fColor=(32768,40777,65535)
		Button button108b, pos={bx,by+by1+20}, size={100,15}, title="Intensity", proc=intensity_analysis
		Button button108c, pos={bx,by+by1+40}, size={100,15}, title="Adaptation", proc=adaptation_analysis //analyze Dan's latency pairs
		Button button108d, pos={bx,by+by1+60}, size={100,15}, title="Columns", proc=column_analysis //analyze Sam's columns
		Button button108e, pos={bx,by+by1+80}, size={100,15}, title="Startle", proc=Display_Waves_Startle //analyze Field Potential's

		
	
		NVAR /z tempfreq = root:A:tempfreq
		If (NVAR_exists(tempfreq))
			SetVariable setvar5,pos={bx+10,by},size={90,15},title="Freq (Hz):"
			SetVariable setvar5,fSize=10,limits={0,1000,0},value= root:A:tempfreq,disable=2 
		Endif

		NVAR /z tempstep1 = root:A:tempstep1
		If (NVAR_exists(tempstep1))
			SetVariable setvar6,pos={bx+10,by+20},size={90,15},title="Step1 (s):"
			SetVariable setvar6,fSize=10,limits={0,1000,0},value= root:A:tempstep1
		Endif

		NVAR /z tempstep2 = root:A:tempstep2
		If (NVAR_exists(tempstep2))
			SetVariable setvar7,pos={bx+10,by+40},size={90,15},title="Step2 (s):"
			SetVariable setvar7,fSize=10,limits={0,1000,0},value= root:A:tempstep2, disable=1 //this is disabled until code is updated
		Endif

		NVAR /z interval = root:A:interval
		If (NVAR_exists(interval))
			SetVariable setvar8,pos={bx+5,by+60},size={95,15},title="Interval (s):"
			SetVariable setvar8,fSize=10,limits={0,1000,0},value= root:A:interval,disable=2 
		Endif

		NVAR /z dInterval = root:A:dInterval
		If (NVAR_exists(dInterval))
			SetVariable setvar9,pos={bx+3,by+80},size={95,15},title="∆Interval (s):"
			SetVariable setvar9,fSize=10,limits={0,1000,0},value= root:A:dinterval,disable=2 
		Endif


		NVAR /z protocol = root:A:protocol
		If (NVAR_exists(protocol))
			PopupMenu popup0 pos={bx,by+100},size={80,15},title="Protocol:", value="Steps;Freq;Pairs", proc=updatePopProtocol
		Endif
		
		by1=280
		CheckBox check108 pos={bx,by+by1}, title="Detect 1st spike",mode=0, value=1
		CheckBox check104 pos={bx,by+by1+20}, title="Latency/period",mode=0, value=1
		CheckBox check105 pos={bx,by+by1+40}, title="Use cursors",mode=0, value=1
		CheckBox check107 pos={bx,by+by1+60}, title="Crop waves",mode=0, value=0
		CheckBox check109 pos={bx,by+by1+80}, title="Accumulate",mode=0, value=0
	
	ElseIf (cmpstr(ctrlName,"button100")==0) // Concatenate settings
		Button button100a, pos={bx,by+190}, size={100,15}, title="Concatenate", proc=concat1,  fColor=(42386,16535,46385)
		CheckBox check102 pos={bx,by+30}, title="Decimate",mode=0, value=0
		CheckBox check107 pos={bx,by+60}, title="Crop",mode=0, value=0

	ElseIf (cmpstr(ctrlName,"button105")==0) // Baseline/analysis settings
		CheckBox check110 pos={bx,by}, title="Use concat. folder",mode=0, value=0

		Button button105b, pos={bx,by+160}, size={100,15}, title="Change points", proc=changeWavepoints, fColor=(65535,54607,32768)
		Button button105a, pos={bx,by+140}, size={100,15}, title="Baseline", proc=base1, fColor=(65535,54607,32768)
		CheckBox check101 pos={bx,by+120}, title="Flip sign",mode=0, value=0, proc=zerosweeps
		CheckBox check106 pos={bx,by+100}, title="Set wave t=0",mode=0, proc=zerosweeps
		NVAR /Z f  //check or uncheck "Zero" checkbox depending on whether import trace was absolute time
		If (NVAR_exists(f))
			Checkbox check106 value=f, disable=2*f, win=zPhys_Settings
		Endif
	
		Button button104a, pos={bx,by+200}, size={100,15}, title="Analyze spikes", proc=analyze_ISI, fColor=(65535,54607,32768)
		CheckBox check103 pos={bx,by+180}, title="Create Layout",mode=0, value=0

		Button button104b, pos={bx,by+60}, size={100,15}, title="Histogram", proc=hist1, fColor=(65535,54607,32768)
		CheckBox check100 pos={bx,by+40}, title="Append histogram",mode=0, value=0, disable=0

		
	Endif
	// Leave the three Analysis Tools category buttons live so a single click can
	// switch directly from Concat to Analysis to Find Spikes.
	Button button100, win=JT_Controls, disable=0
	Button button105, win=JT_Controls, disable=0
	Button button108, win=JT_Controls, disable=0
	TabControl MPtab1, win=JT_Controls, value=1
	ControlUpdate /A /W=JT_Controls
	zPhys_PositionSettingsPanel()

	// Return focus to the main panel; zPhys_Settings is now independent, so it should not capture clicks.
	DoWindow /F JT_Controls
End
////////////////////////////////////////////////////////////////////////////////////////////////////
// Update protocol controls for Steps, frequency trains, or paired-pulse analysis.
Function updatePopProtocol (ctrlName,popNum,popStr) : PopupMenuControl
	String ctrlName
	Variable popNum	// which item is currently selected (1-based)
	String popStr		// contents of current popup item as string

	NVAR /z protocol = root:A:protocol
	NVAR /z interval = root:A:interval
	NVAR /z dinterval = root:A:dinterval

	NVAR /z tempstep1 = root:A:tempstep1
	NVAR /z tempstep2 = root:A:tempstep2
	NVAR /z tempfreq = root:A:tempfreq

	protocol = popNum
	
	If(protocol==1)
		SetVariable setvar5 win=zPhys_Settings, disable=2 //tempfreq
		SetVariable setvar6 win=zPhys_Settings, disable=0 //tempstep1
		SetVariable setvar8 win=zPhys_Settings, disable=2 //interval
		SetVariable setvar9 win=zPhys_Settings, disable=2 //interval
		interval = 0
	ElseIf(protocol==2)
		SetVariable setvar5 win=zPhys_Settings, disable=0 //tempfreq
		SetVariable setvar6 win=zPhys_Settings, disable=2 //tempstep1
		tempstep1= 1/tempfreq
		SetVariable setvar8 win=zPhys_Settings, disable=2 //interval
		SetVariable setvar9 win=zPhys_Settings, disable=2 //interval
		interval = 0	
		dinterval = 0
	ElseIf(protocol==3)
		SetVariable setvar5, win=zPhys_Settings, disable=2 //tempfreq
		SetVariable setvar6, win=zPhys_Settings, disable=0 //tempstep1
		SetVariable setvar8, win=zPhys_Settings, disable=0 //interval
		SetVariable setvar9 win=zPhys_Settings, disable=0 //interval

		interval = 0
		dinterval = 0	
	Endif	
	

End
////////////////////////////////////////////////////////////////////////////////////////////////////

// Menu entry point. loadNum=0 starts fresh; loadNum=1 rebuilds/reloads the panel.
Function Start_A(loadNum)
	Variable loadNum
	
	If (loadNum==1)
	
		SVAR /Z input_type 
		If (SVAR_exists(input_type)==0)
			String /G root:A:input_type = ""
			String /G root:A:stim_type = ""
		Endif

	ElseIf (loadNum==0)
		NewDataFolder/O/S root:A
		String /G tempfolder = ""
		String /G tempfilefolder = ""
		String /G tempwave = ""
		String /G input_type = ""
		String /G stim_type = ""
		String /G data_type = "" //Sutter; HEKA; ABF etc...

		
		Variable /G tempfreq = 5
		Variable /G tempstep1 = 1/tempfreq
		Variable /G tempstep2 = 1/tempfreq
		Variable /G interval = 0
		Variable /G dinterval = 0
		Variable /G protocol =1
		Variable /G spikeamp //-1e-11
		Variable /G spiketime //1e-3
		Variable /G eventamp //10e-12
		Variable /G sweepStartnum = 1 // e.g., 1
		Variable /G sweepEndnum = 60 // e.g., 60
		Variable /G sweepCurrent = 1 // e.g., 60

		String /G extraGain = "no" // "yes" for microphonics
		Variable /G extraGain1 = 500 // for Axon 200B for microphonics
		Variable /G extraGain2 = 100 // for Brownlee Amplifier
				
		DoWindow /K ISI_table	//Kill table of accumulating ISI values
		Edit /N= ISI_table /W=(0,0,400,200) /Hide=1 /K=3 //Make new table for accumulating ISI values

		DoWindow /K FFT_table	//Kill table of accumulating FFT values
		Edit /N= FFT_table /W=(0,0,400,200) /Hide=1 /K=3 //Make new table for accumulating values

		NewDataFolder/O root:A:Avg
		NewDataFolder/O root:A:Concat
		NewDataFolder/O root:A:FFT1
		NewDataFolder/O root:A:V
		NewDataFolder /O root:Packages
		NewDataFolder /O/S root:Packages:MPVars
		String /G RootFolder_list=""
		SetDataFolder Root:
	Endif		

		
	//Change the following paths based on the machine
	String tempPath1 = SpecialDirPath("Desktop", 0, 0, 0)
	Variable len1 = strlen(tempPath1)		// strlen(NULL) returns NaN
	If (numtype(len1) == 2)					// fullPath is NULL?
		Print "SpecialDirPath returned error."
	Endif

	NewPath /O /Q Desktop, tempPath1

	String tempPath2 = SpecialDirPath("Documents", 0, 0, 0)
	Variable len2 = strlen(tempPath2)		// strlen(NULL) returns NaN
	If (numtype(len2) == 2)					// fullPath is NULL?
		Print "SpecialDirPath returned error."
	Endif

	NewPath /O /Q /Z HEKAPath, tempPath2+"Research Data:HEKA:"
	PathInfo HEKAPath
	If (V_flag==0)
		NewPath /O /Q HEKAPath, tempPath2
	Endif
	
	
	NewPath /O /Q /Z ABFPath,  tempPath2+"Research Data:ABF1:"
	PathInfo ABFPath
	If (V_flag==0)
		NewPath /O /Q ABFPath, tempPath2
	Endif
		
	SetupMainPanel(loadNum)

End


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

// Create the main JT_Controls panel and all tab controls.
Function SetupMainPanel(loadNum)
	Variable loadNum
	Variable tabx=20, taby=160, bx=100, bx2=15, by=25
	Variable i
	String tempstring1
	SVAR tempfolder = root:A:tempfolder	
	SVAR tempfilefolder = root:A:tempfilefolder
	SVAR tempwave = root:A:tempwave

	KillWindow /Z zPhys_Settings
	DoWindow /K JT_Controls
	
	
	String info = IgorInfo(0)
	String screen1RectStr = StringByKey("SCREEN1", info)		//e.g., "DEPTH=23,RECT=0,0,1280,1024"
	Variable depth, left, top, right, bottom
	sscanf screen1RectStr, "DEPTH=%d,RECT=%d,%d,%d,%d", depth, left,top, right, bottom
	
	String platform= UpperStr(igorinfo(2))
	If (cmpstr(platform,"WINDOWS")==0)
		NewPanel /N=JT_Controls /W=(right-370,top,right,600) /K=2
	Else	
		NewPanel /N=JT_Controls /W=(right-440,top,right-70,600) /K=2
	Endif
	ModifyPanel /W=JT_Controls fixedSize=1, noEdit=1 //******Lock the panel from editing!
	Display /HOST=JT_Controls /N=embedwin /W=(0.05,0.6,0.95,0.9) /K=1
	// Main-panel event-threshold slider for the embedded trace graph.
	// Keep the original, wider geometry because it is easier to see and grab on macOS.
	Slider slider2, win=JT_Controls, pos={350,360},size={80,60},proc=updatemainAmp, ticks=0,live=0,side=0, title=""

	SetActiveSubwindow ##


	//Info and controls that should always be displayed; i.e. controls above the tabs
	SetDrawLayer ProgFront
	DrawRRect 5,35,365,120
	SetDrawEnv fsize= 18, fillbgc=(49151,53155,65535)
	DrawText 40,90,"Trapani Lab\r  analysis"
	SetDrawEnv fsize= 10, fillbgc=(49151,53155,65535)
	DrawPict 160,50,0.4,0.4,ProcGlobal#JT_fishpict
	
	//Select Series popup menu
	PopupMenu popupmenu1, pos={tabx+80,10}, size={250,20}, bodywidth=0, mode=0, proc=Select_Series, fsize=11
	
	TitleBox title0, pos={10,560}, frame=0,  title="Displayed Wave:"
	TitleBox title1, pos={90,560}, frame=0, variable=tempwave
	TitleBox title2, pos={10,580}, frame=0,  title="Series Folder:"
	TitleBox title3, pos={90,580}, frame=0, variable=tempfolder
	Button buttonA, pos={300,555}, size={30,20}, title=">", proc=Display_NextWave
	Button buttonB, pos={260,555}, size={30,20}, title="<", proc=Display_PrevWave
	
	TitleBox title4, pos={250,305}, frame=0, title="Spike properties"
	SetVariable setvar0,pos={250,320},size={100,18},limits={0,1,0},format="%.0W1Ps",title="Width"	//format %g reduces precision of value for display
	SetVariable setvar1,pos={250,340},size={100,18}, limits={-1000,1000,0},proc=updatemain, format="%.1W1PA", title="Height"	//format %g reduces precision of value for display
	SetVariable setvar2,pos={010,340},size={80,18},limits={1,10000,0}, title="Waves:",fSize=10
	SetVariable setvar3,pos={090,340},size={70,18},limits={1,10000,0}, title="to:",fSize=10
	
	SetVariable setvar4,pos={240,580},size={90,18},limits={1,10000,0},title="Wave#:",fSize=10, proc=Display_CurrentWave
	
			
	//Set up Control Panel tabs
	TabControl MPtab1, win=JT_Controls, pos={5,130}, size={360,420}
	TabControl MPtab1, proc=MPTabProc, tablabel(0)="File Tools", tablabel(1)="Analysis Tools", tablabel(2)="Display Tools"
	
	//Controls for tab0, File Info
		
	// File Tools layout: prioritize the normal SutterPatch PXP workflow.
	// Load Sutter PXP imports a SutterPatch .pxp into the current experiment;
	// Select Sutter attaches zPhys to an already-open SutterPatch folder.
	Button button009, pos={tabx,taby}, size={bx+15,by}, title="Load Sutter PXP", proc=Import_PXP_File, fColor=(42386,16535,46385)
	Button button008, pos={tabx+bx+bx2+15,taby}, size={bx,by}, title="Select Sutter", proc= Load_Sutter_Wave, fColor=(0,0,0)

	Button button000, pos={tabx,taby+2*by}, size={bx,by}, title="Load HEKA", proc=Import_HEKA_File
	Button button005, pos={tabx+bx+bx2,taby+2*by}, size={bx,by}, title="Load ABF", proc= Import_ABF_File
	Button button007, pos={tabx+2*(bx+bx2),taby+2*by}, size={bx,by}, title="Load CSV", proc= Import_CSV_File

	Button button006, pos={tabx,taby+4*by}, size={bx,by}, title="Load Wave", proc= Select_Wave
	Button button001, pos={tabx+bx+bx2,taby+4*by}, size={bx,by}, title="Select Wave", proc=Select_Wave
	Button button003, pos={tabx+2*(bx+bx2),taby+4*by}, size={bx,by}, title="Save Wave", proc=save1

	Button button002, pos={tabx,taby+6*by}, size={bx,by}, fColor=(43690,43690,43690),title="Select Folder", proc=Select_Folder
	Button button004, pos={tabx+bx+bx2,taby+6*by}, size={bx,by}, fColor=(43690,43690,43690)  // Load Series or Reload ABF button

	
	CheckBox check000 pos={15,100},fColor=(0,0,65535 ), title="*",mode=0, value=1, disable=0
	CheckBox check0001 pos={15,85},fColor=(0,0,65535 ), title="Adjust for retina display",proc=adjustRetinaDisp, mode=0, value=0, disable=0

	//	SetDrawLayer UserFront
	//	DrawText /W=JT_Controls 45,100,"sweeps are baseline subtracted"
	
	//Controls for tab1, Analysis Tools
	Button button100, pos={tabx,taby}, size={bx,by}, title="Concatenate", proc=JT_settings
	Button button103, pos={tabx+2*(bx+bx2),taby+4*by}, size={bx,by}, title="Average", proc=average1
	Button button105, pos={tabx+2*(bx+bx2),taby}, size={bx,by}, title="Analysis", proc=JT_settings
	Button button106, pos={tabx+bx+bx2,taby+4*by}, size={bx,by}, title="FFT/Area", proc=fft_wave1
	Button button107, pos={tabx,taby+4*by}, size={bx,by}, title="Vector", proc=vector1
	Button button108, pos={tabx+bx+bx2,taby}, size={bx,by}, title="Find Spikes", proc=JT_settings
	
	//Controls for tab2, Display Tools
	Button button200, pos={tabx,taby}, size={bx,by}, title="Display Wave", proc=Display_Waves
	Button button201, pos={tabx+bx+bx2,taby}, size={bx,by}, title="Display Analysis", proc=Display_Wanalysis
	Button button202, pos={tabx+2*(bx+bx2),taby}, size={bx,by}, title="Display Hist", proc=Display_HistWaves
	Button button203, pos={tabx+2*(bx+bx2),taby+4*by}, size={bx,by}, title="Columns to Table", proc=Table_Waves
	Button button204, pos={tabx,taby+4*by}, size={bx,by}, title="Save Pict(s)", proc=Save_Pict
	Button button205, pos={tabx,taby+6*by}, size={bx,by}, title="Save Binary", proc=Save_Binary
	Button button209, pos={tabx+bx+bx2,taby+4*by}, size={bx,by}, title="Modify Graphs", proc=modifyGraphs
	Button button210, pos={tabx+bx+bx2,taby+6*by}, size={bx,by}, title="SDP Panel", proc=addCategoryToSDP
	Button button211, pos={tabx+2*(bx+bx2),taby+6*by}, size={bx,by}, title="+Bars to SDP", proc=addCategoryToSDP
	Button button206, pos={tabx+2*(bx+bx2),taby+2*by}, size={bx,by}, title="Waterfall Plot", proc=Waterfall_waves
	Button button207, pos={tabx,taby+2*by}, size={bx,by}, title="Display Stim", proc=Display_StimWave
	Button button208, pos={tabx+bx+bx2,taby+2*by}, size={bx,by}, title="Tile Graphs", proc=Tile_graphs
	CheckBox check201 pos={tabx+bx,taby+30}, title="Multiple waves",mode=0, value=1

	If (loadNum==0)
		MPTabProc ("start",0)
	Else
		MPTabProc ("reload",0)
	Endif
End



////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Toggle line clipping for high-resolution/Retina displays.
Function adjustRetinaDisp (ctrlName,checked) : CheckBoxControl
	String	 ctrlName
	Variable checked
	String cmd

If  (checked==1)
sprintf cmd, "SetIgorOption ClipLineThickness=%d", 1000
Execute cmd
else
sprintf cmd, "SetIgorOption ClipLineThickness=%d", 0
Execute cmd
Endif

//DisplayHelpTopic "Graphs and High-Resolution Displays"

End

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
//
// Tab-control callback and shared panel-state updater.
Function MPTabProc(loadName,tab)
	String loadName
	Variable tab

	//Note: loadName = "MPtab1" when switching tabs
	If (cmpstr(loadName,"MPtab1")!=0)
		String PopList = "Generate_PopList()" //("+loadName+")"
		PopupMenu popupmenu1,win=JT_Controls,fColor=(0,0,0), disable=(tab!=1), Mode=0, value=#PopList 
	Endif

	//Create visible Buttons for only Active Tabs
	Button button000, disable= (tab!=0)
	Button button001, disable= (tab!=0)
	Button button002, disable= (tab!=0||cmpStr(loadName,"start")==0)
	Button button003, disable= (tab!=0||cmpStr(loadName,"start")==0||cmpstr(loadName,"reload")==0)
	Button button005, disable= (tab!=0)
	Button button006, disable= (tab!=0)
	Button button007, disable= (tab!=0)
	Button button008, disable= (tab!=0)
	Button button009, disable= (tab!=0)

	CheckBox check000, disable= (tab!=0)
	
	Button buttonA, disable= (tab==0)
	Button buttonB, disable= (tab==0)
	
	TitleBox title4, disable= (tab!=1)
	SetVariable setvar0,disable= (tab!=1)
	SetVariable setvar1,disable= (tab!=1)
	
	
	SetVariable setvar2, disable= (tab==0)
	SetVariable setvar3, disable= (tab==0)
	SetVariable setvar4, disable= (tab==0)
	
		
	controlInfo /W=JT_Controls check000
	If  (tab==0&&V_Value==1)
		SetDrawLayer /W=JT_Controls /K UserFront	
		SetDrawLayer /W=JT_Controls UserFront
		SetDrawEnv textrgb=(0,32000,65535 )
		DrawText /W=JT_Controls 40,115,"\\Z10imported traces will be baseline subtracted"
	ElseIf  (tab==0&&V_Value==0)
		SetDrawLayer /W=JT_Controls /K UserFront	
		SetDrawLayer /W=JT_Controls UserFront
		SetDrawEnv textrgb=(3200,32000,3200 )
		DrawText /W=JT_Controls 40,115,"\\Z10imported traces will NOT be baseline subtracted"
	ElseIf  (tab!=0&&V_Value==0)
		SetDrawLayer /W=JT_Controls /K UserFront	
		SetDrawLayer /W=JT_Controls UserFront
		SetDrawEnv textrgb=(3200,32000,3200 )
		DrawText /W=JT_Controls 20,115,"\\Z10Note: imported traces are NOT baseline subtracted"	
	ElseIf  (tab!=0&&V_Value==1)
		SetDrawLayer /W=JT_Controls /K UserFront	
		SetDrawLayer /W=JT_Controls UserFront
		SetDrawEnv textrgb=(0,32000,65535  )
		DrawText /W=JT_Controls 20,115,"\\Z10Note: imported traces are baseline subtracted"	
	Else
		SetDrawLayer /W=JT_Controls /K UserFront	
	Endif

	
	SVAR data_type = root:A:data_type
	If (cmpstr(data_type,"ABF")==0)
		Button button004, disable= (tab!=0||cmpStr(loadName,"start")==0||cmpStr(loadName,"reload")==0), title="Reload ABF", proc= Import_ABF_Data
	ElseIf (cmpstr(data_type,"HEKA")==0)
		Button button004, disable= (tab!=0||cmpStr(loadName,"start")==0||cmpStr(loadName,"reload")==0),title="Load Series", proc= Import_HEKA_Series
	ElseIf (cmpstr(data_type,"SUTTER")==0)
		Button button004, disable= (tab!=0||cmpStr(loadName,"start")==0||cmpStr(loadName,"reload")==0),title="Load Series", proc= Load_Sutter_Wave
	Else
		Button button004, disable=1
	Endif
	
	
	
	PopupMenu popupmenu1,win=JT_Controls, disable= (cmpStr(loadName,"start")==0||cmpStr(loadName,"reload")==0)
	
	Button button100, disable= (tab!=1)
	Button button103, disable= (tab!=1)
	Button button105, disable= (tab!=1)
	Button button106, disable= (tab!=1)
	Button button107, disable= (tab!=1)
	Button button108, disable= (tab!=1)
	Slider slider2, win=JT_Controls, disable= (tab!=1)
	

	//
	

	CheckBox check201, disable= (tab==0)
	Button button200, disable= (tab!=2)
	Button button201, disable= (tab!=2)
	Button button202, disable= (tab!=2)
	Button button203, disable= (tab!=2)
	Button button204, disable= (tab!=2)
	Button button205, disable= (tab!=2)
	Button button206, disable= (tab!=2)
	Button button208, disable= (tab!=2)
	Button button209, disable= (tab!=2)
	Button button210, disable= (tab!=2)
	Button button211, disable= (tab!=2)

	If (tab==2&&cmpstr(data_type[0,2],"ABF")==0)
		Button button207, disable=2
	Else
		Button button207, disable= (tab!=2)
	Endif
		
	//	SetVariable setvar0, disable= (str2num(loadNum)==0||str2num(loadNum)==1)
	//	SetVariable setvar1, disable= (str2num(loadNum)==0||str2num(loadNum)==1)
	//	SetVariable setvar2, disable= (str2num(loadNum)==0||str2num(loadNum)==1)
	//	SetVariable setvar3, disable= (str2num(loadNum)==0||str2num(loadNum)==1)
	//	SetVariable setvar4, disable= (str2num(loadNum)==0||str2num(loadNum)==1)

	
	//loading panel for 1st time	
	//If (tab==0&&Ftab==0)
	If (tab==0&&cmpStr(loadName,"start")==0)

		TabControl MPtab1, value=0, disable=0
		TabControl MPtab1, value=1, disable=2
		TabControl MPtab1, value=2, disable=2
		Button button009, fColor=(42386,16535,46385)
		Button button008, fColor=(0,0,0)
		TitleBox title0, disable=1
		TitleBox title1, disable=1
		TitleBox title2, disable=1
		TitleBox title3, disable=1


		//if reloading panel		
	Elseif (tab==0&&cmpStr(loadName,"reload")==0)
		
		TabControl MPtab1, value=0, disable=0
		TabControl MPtab1, value=1, disable=2
		TabControl MPtab1, value=2, disable=2
		Button button009, fColor=(42386,16535,46385)
		Button button008, fColor=(0,0,0)
		Button button002, fColor=(42386,16535,46385)
		TitleBox title0, disable=1
		TitleBox title1, disable=1
		TitleBox title2, disable=1
		TitleBox title3, disable=1


	Else
		Button button009, fColor=(42386,16535,46385)
		Button button008, fColor=(0,0,0)
		Button button002,fColor=(43690,43690,43690)
		TabControl MPtab1, value=0, disable=0  //show tab 0
		TabControl MPtab1, value=1, disable=0 //show tab 1
		TabControl MPtab1, value=2, disable=0 //show tab 2
		TitleBox title0, disable=0
		TitleBox title1, disable=0
		TitleBox title2, disable=0
		TitleBox title3, disable=0

	Endif	


	//		String ISIwaves = WaveList("*_ISI", ";", "")
	//		String ISIwave = Stringfromlist(0,ISIwaves)
	//		Wave /Z wavecheck1 = $ISIwave
	//		String savedDataFolder = GetDataFolder(1)	// Save
	//		SetDataFolder root:A:Concat:
	//		Wave /Z wavecheck2 = WaveRefIndexed("",0,4) 
	//		SetDataFolder savedDataFolder			// and restore


	// Keep the settings subpanel only on the Analysis Tools tab.
	// Do not disable the main Concat/Analysis/Find Spikes buttons based on which
	// settings subpanel is present; leaving them enabled makes switching settings
	// groups reliable with one click.
	DoWindow zPhys_Settings
	Variable settingsPanelExists = V_flag
	If (settingsPanelExists!=0 && tab!=1)
		KillWindow /Z zPhys_Settings
		settingsPanelExists = 0
	ElseIf (tab==1)
		Button button100, win=JT_Controls, disable=0
		Button button105, win=JT_Controls, disable=0
		Button button108, win=JT_Controls, disable=0
		zPhys_PositionSettingsPanel()
	Endif
	
	// Check or uncheck the "Zero" checkbox depending on whether the import trace
	// already starts at t=0. Only touch the subpanel control if the subpanel exists.
	If (settingsPanelExists!=0)
		NVAR /Z f 
		ControlInfo /W=zPhys_Settings check106
		If (V_flag!=0&&NVAR_exists(f))
			Checkbox check106 value=f, disable=2*f, win=zPhys_Settings
		Endif
	Endif	

	TabControl  MPtab1, win=JT_Controls, value=tab, labelBack=0 //(30000,30000,30000)
End


//******************************************************************************************************
//******************************************************************************************************

// Refresh panel popup lists and embedded graph contents after loading/selecting data.
Function UpdateControlPanel (ctrlName, popStr, loadNum)
	string ctrlName 
	String popStr		// contents of current popup item as string
	Variable loadNum
	Variable n
	string popstrpath 	//Holds complete path to the folder selected in popupmenu1
	string tempstring1
	string tempstring2
	SVAR tempfolder = root:A:tempfolder
	SVAR tempfilefolder = root:A:tempfilefolder	
	SVAR RootFolder_list = root:Packages:MPVars:RootFolder_list
	SVAR data_type = root:A:data_type

	tempstring1 = popstr[0]
	If (cmpstr(tempstring1,"")!=0)
		popstrpath = "root:"+popstr+":"
	Else
		popstrpath = "root:"
	Endif


	//Generate list of the names of Data folders contained in the root directory, skipping the MPVars Folder
	If (cmpstr(ctrlName,"LoadSUTTERFolder")==0 ||cmpstr(ctrlName,"LoadWave")==0 ||cmpstr(ctrlName,"Import_HEKA_File")==0)
		
		SetDataFolder root:Packages:MPVars:
		
		//Root Folders
		String FolderName
		String ListofFolderNames=""
		Variable index=0
		String rootDF = "root:"
		String currentDF
		do
			Foldername = GetIndexedObjName(rootDF,4, index)
			if (strlen(Foldername) == 0)
				break
			endif
			If (DataFolderExceptionCheck(Foldername)==1)		//MPVars does not need to be added to the list of folders for display
				ListofFolderNames+=Foldername+";"
			Endif
			index+=1
		while(1)

		RootFolder_list = ListofFolderNames
		
		//Series folders within Data folders		
		ListofFolderNames=""
		index=0
		If (cmpstr(ctrlName,"LoadSUTTERFolder")==0)
		currentDF = "root:"+data_type+":"+tempfilefolder+":"
		Else
		currentDF = "root:"+tempfilefolder+":"		
		Endif
		do
			Foldername = GetIndexedObjName(currentDF,4, index)
			if (strlen(Foldername) == 0)
				break
			endif
			ListofFolderNames+=Foldername+";"
			index+=1
		while(1)

		String Folderlist = tempfilefolder+"_list"
		String /G $Folderlist = ListofFolderNames
	
	Endif


	SetDataFolder popstrpath
	MPTabProc (ctrlName,loadNum)

	PopupMenu popupmenu1,win=JT_Controls,title=tempfolder, mode=0


	//REMOVE traces in JT_Controls panel so that incoming wave can be killed during rename below
	String graphNameStr = "JT_Controls#embedwin"
	String graphtraces=TraceNameList(graphNameStr,";",1)

	If (cmpstr(graphtraces,"")!=0)
		For(n=0;n<itemsinlist(graphtraces);n+=1)
			String temptrace=stringfromlist(n,graphtraces)
			RemoveFromGraph /W=JT_Controls#embedwin $temptrace
		Endfor
	Endif
	
End		//End of UpdateControlPanel


//******************************************************************************************************
//******************************************************************************************************

// Return 1 for user data folders and 0 for internal/program folders.
Function DataFolderExceptionCheck (Foldername)

	String Foldername

	//check to see if Foldername is a folder containing program info or user data
	//return 1 if the folder contains user data, 0 if it contains program info
	
	Variable foldertype = 1
	
	StrSwitch (Foldername)
		case "MPVars":
		case "Packages":
		case "A":
		case "SutterIPA":
		case "SutterPatch":
		case "SUTTER":
		case "ABF":
		case "HEKA":


			foldertype = 0
			break
	endswitch
	
	Return foldertype
	
End		//end of DataFolderExceptionCheck

//******************************************************************************************************
//******************************************************************************************************
// Build the dynamic series-folder popup menu contents.
Function /S Generate_PopList()
	SVAR tempfilefolder = root:A:tempfilefolder	
	SVAR data_type = root:A:data_type
	String ListofFolderNames=""
	Variable index=0
	String FolderName
	String currentDF
	
	//If Restart or empty tempfilefolder, then check Root Data Folders

	PopupMenu popupmenu1,win=JT_Controls,  disable=0

	If (cmpstr(tempfilefolder,"")==0)
		currentDF = "root:"
		do
			Foldername = GetIndexedObjName(currentDF,4, index)
			if (strlen(Foldername) == 0)
				break
			endif
			If (DataFolderExceptionCheck(Foldername))		//Packages and "A" does not need to be added to the list of folders for display
				ListofFolderNames+=Foldername+";"
			Endif
			index+=1
		while(1)
		SVAR RootFolder_list = root:Packages:MPVars:RootFolder_list
		RootFolder_list = ListofFolderNames
	
	Else	
		If (cmpstr(data_type,"SUTTER")==0)
		currentDF = "root:"+data_type+":"+tempfilefolder+":"
		Else
		currentDF = "root:"+tempfilefolder+":"
		Endif
		do
			Foldername = GetIndexedObjName(currentDF,4, index)
			if (strlen(Foldername) == 0)
				break
			endif
			ListofFolderNames+=Foldername+";"
			index+=1
		while(1)
	
	Endif
		
	If (cmpstr(ListofFolderNames,"")==0)
		PopupMenu popupmenu1,win=JT_Controls,  disable=2
	Endif

	Return  ListofFolderNames

End	
//******************************************************************************************************
//******************************************************************************************************


//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////
//Image for JT_Controls panel
// PNG: width= 502, height= 80
Picture JT_fishpict
ASCII85Begin
M,6r;%14!\!!!!.8Ou6I!!!&n!!!!q#R18/!:/<>qZ$Tr$#iF<ErZ1J'*&"?'*/*%S/;5+!#]lI=EI
J[Aor6*Eb,5:A8bpg+A$EYB4XtP@:XY'a^mR7!&;Pd6pXdsg?bA#YA@:Jn$h8;UWLW5A?l=K)[m!_N
f_%.H<<KhFD1/$p^"&pNufn:d3;-5[Y2IfQtHsICqsGo"qs\UiLXE4qqH%ZETUMAY#MfDmkpn=<UF)
"C9AGoJ)kUoJ,]&3s*Jd,npaCmg1[7@2VMi>,5qDrs$$8!5Q5ZnpV6b,j>(VEr9\EPMuNuKT3_9Xs1
A4(mGf;gplc(%/t>&g8Pe&'QDA:K&+I=d5@<-1D53(K3fD5WTE"iP'n:irBDU5prjDXiA;5ET2*9q@
km:.1_WgA654OKaU)XKEDZFdKfe]c-K?jSrIDijEb#=n;"*m.]::dY]haSQ%F:8;9ND*F9R6e@dgkQ
e\NF:h.HedY)%po,STn)<cp.t$"p(!NNcP`6u05/DXK)&7&GQ.BX5G#Roi*Yu*(X02a)mF7fd7+?E5
F<Wg<TY/VlpHEt']NH/:[]lMofNBKP.'NQd-<O9?ZmOfM!Lk@."KWPc"R4T7ils:jP"CQ4aH<kT=P(
#7dFO522YSg)CV%FLQ[Vi]MQ_Gh$(N<Xk1#TqpGI;J.OTP#it>BJXc,.6'h5H!WdYpkDe3hE<L@7_6
n#8UG#'+P@+=[QRC+(`\UA]q93K3?Is$QCg^MtPk+^Q=fmsO*Xe6\Z"%GWhqTr%`G6gOQNu\Ed&:Z-
ls7olPFqd6dHaf\ni*3?s3*(KY[Hl[bS=3a"T@9iJ(TbRktcg*:4"'tWS)h#N+u?i6]-h1-kl'5?s=
,\&1L^uAu"IdKh3D3FFC=c^V9.GeR!JK"O.rp[)BTi%&Lc5f>%<-#:N`*/"MIHH-:Zn5/??M>T81un
9M.UIo`t)UXsdq"pVdj4<4g7GBE!Ve_W5m59a"rpXp"FI?^SQgBF`qQ!-+MNq)Mc!g:gPXV<?ZN!40
(1Di:Pg!@B!po(a$`X4m:3b-Gc!#L4CB@]Mp_Qe]A"EHBkkT`;=riW(Fn"JY<p:!-N]u?_P!W,KF6U
u6oRkP&rYcqrpGaR.aJ,.8pMV!__Q6f"+qd,9Wr'!j1Cu-n^JYk9cg0A-&^rf,Je"!C"0^c=L%en#2
4=Au9Y6ECc8-&A[0t=:7dNp"*9FDj2*'mrip\0V:;#i;5s%pjt5ji.,B([>5qnjNTE6$..r8JN"!Ua
,1eD<,l&"qJW:ilN.10DT7iF9>097]McMP'n?Vn;8:"fChi)?]fkms`kM:<$BDMH\28D[$$94mcsSN
1]Ep!=&6eBn+V8MUL\6UYqfKG:YJ(3=^]uZ_kf_`ko:gn=1fVrD.q>dr)hB_%JI22.2CE?ph`4jSt8
iH)q*u?5nf<;MlKOs6gmo.5G2&/dAg+Rl9+q07E(X:VQS:n*PAo`JYO.H%p;?cu4C)S"4]#CJN2\JJ
t@FM[BlXjJ$@'#\*p@NO\%l#&>"7f>%=Xl2-5XIeX8"GW[gARC%`(5eYQ)WX/ir^.RN@(jYB7*4Vs`
MYsrH!!.U$?+jt[C"A8V+DQKq1pdPV9,-ubHCq9!H\XD[09ig.rqQH\It,g"15C:8:$]L42,nXhPBU
efLmEi\rlo]5Our3[J,]&]pV6b,h0K+ic[G5&YIIZ96sY991BHiY>bi5F$Y65SMIb?#)b_O]X2O28n
:`O^bUdfK$j=SdDt(uFZf!s;orMeCLqQ][Tk$<"rEQCbJ1qNPDb32:Xl^1&(j!$=J32q68t+a;pOd(
s(jT.tBAE8Of:lEb&*J*H`&Ym?>7'r.E&!VB)g?jeo.4VF?/X!j,;aFi'IqE;Yj92)4'!iUM];WBVE
72g5%G.4"QXqAir@OOT)\`O<rnk^6lmXqqG2S2PNr,:SL?IBXnWt,k-n^kZBoDnIZ>h[F3.]bZ7*'c
$!A+dDM9V]bi*#eKj&4X[#B?k^n0^b(BV80OC4iHUY/s(k1WBMTb$d*0]eHab8S2;'&4)Eo3":=?l.
$EZb(K7cc:V-3L?DgT8`fnpCPYU.fq<VD`4;#YjDPQ3CrOAn-6r_41GFDbf_m5(ojFX[Jj[u\0[GKm
'Y0.25*JkHN9bWcR;=p@A+r/7(5KSqpX'[s'g:Vr;9Ais&l4/!P;7f?H`,=>K.esZUU!>qWQ&IIeL,
(ldri<F]Sms$9.mRZ[>`fc2o5qlc8]^4tRV[5TYIu'6S])a]e0[0Pr6m*Xeuu2@fhY7n\.1Rl`C\lk
_8Tp/#,c7btq4_I9;i5\<&10b`t>p*d+imb3.:X$ChOA-&G@F-%sR[=%Muhi:u5OCt_a\u[Sk-?]R(
Z^@nR[P!AcqqL#bi>[+`E%a'dih7<7otW21"3@?frSeX.fJ-$dU.gd&R)ijA83*-SGmNDFTEs=fj4@
R\>uC48>#GLe>#<g?a%tCEdj5:L":$MWCF8a7!0;tV9U]I`Ya^>tQC*<=TYr5YA0E+"&CqE'Ik2MM^
a+^TGR:dBW]l>/n2-$gF.Vun;rq$W^j95=n*F79pXK;VTP\5O@K$6`2[e(JaCSVh#J>QUK-0HO&#k,
\H08ggi.?"QCdEFNlgmED2\-a.N12f6i)$a@FFC(UHUE>YH-^io0&:/XOIo-J+=LA$8tRo\M)2nG,^
C3ZEqEIa*A)E/s*rlHHK_%Q>[+jr8g\iH&Y.Ob^t*$OU-<I">i(Y[G5qO8mo%-!`klMAr&`g3cJFpu
Pa$QtenrUD%.Z'$q9)P7q\VR;$'>I'5oUjsbe"X(27,&4e>-W@8?Y.9OgkW+>;edJD%A3:1mMffn1O
;lqfn"&hGlNa$OM3pCFl=9%4)D$fGY3)B/R<7UbOSP3LDOMh_WVgB$Q\DT9$rZXe<RQMh($i7KKL76
@pMVe;ACN`;\(q5aO5ipXd(?2-53]\N?p"GA'neLCjMFn3M-mGJF%2SV3.:.fjPFpr579TK\Xtpr58
\*XDtHaS)m$k%m!o@EE&cFon%@$<5ecXA]F5YJ:)5`RC\fJ`4rYF&p*8Fk=:Ae<rDlT7Tun7Ap@glq
N1g>')fW1>e-5Xl<jW*`5arflRi#3G2#U%=$:qqilja&7f3LWs#'Roi0+A8I3CFSq@hpR1!/2Nn98V
Jn$<a'\sO<S8g]$0\r*7#UR,D"q*m.04]!5QVeIX%Kc!cgL3,Q#)sVI*5ISg>U72cn$qD<fnqomg:,
jXbO0Mpa$#_B,m*APg0gV4f`P,7?n.V!gh9=_H_32Q`dHMGDRG@COcfK$2ZFU\Hmb5@X:[<$3&?NV7
5&u7%b+^3YE-fGg=fhu"7J%K1[!AGh.**/&7f4EAsLFQLFC53X$@F7Gb'P[T`L?SZ&%Gd6:4HiaIao
p5"$uTXKAOGZbL!\r1&GuYclpKF&TMLs8;%E0CDmVjLq8u$j<]YEf2UUr8sBq@1X^kR6W_3II7(p2"
fFZLF0ff6FsTB%Ym"N+>8-$$W#%8a%Q[`AgS)l'skp*-A1hA)/0WQ_7-fF7Nb?dIefMW3gGg'Q2HE=
T0C&eq?ZH*ce`EEa;0PsH)^moQQT*dO$eVQBEa4/5Rb@I+p^Tgf\@2PZN`VFff$Pe7besS&C[G9<T0
tJC%p(_3$b@Q5TGd!C.t#EWJM!2e2I&&^@IPQYC?/F<K5bgDGAtnl!]N:?T_NlS)3e7?:KhGh.>HL*
dk*dcS6&J_7HSE[ee#dI.4rm,@CsqN/r*o%AM0oaLn),-7s9@qG^oE4h"^/iYk@K[;[ZcN8In*(j)W
DUB]SC/9hou\YYEd$r.MPUSV?hNJ6T1C_6lG+:uk:.5Rl6\Jct$(a'hnnhEmI/@g3Un?u_cohUUan"
-jEZj(*UE*D^=af'GB,F_Ba"rcojJ,J>t=WIsa[b2Pfk<AXNX+K?`,l5KH.al1c^\ZKahO-IO/#cOe
J>B,X6mdP_K$B"g"U9K2`-[jQF6LH#<L!'/NK6Gq"ZJK7<6CtB1."&1$X%`"Q@pe+e?j[YK-aG:UXl
U[&D[D9Q@L@d.N!9H"[q8E&3kMH5:a++ka3jNIIirc]ODrojIFKblsm8>&Wo'T3ZAUsS;g-+*5M"#E
_09<4gaJ"IeL*L8Z2LTK-1$LU1I8c>g_WYHHMXA6o"o``L+"YY!]FgRK:8E^lI*<^TmSo\5C0@eZXG
0'*L;]bW-(Uc?Tg^;Zk\+WZEhT8oe]'JX4:h]<Z!BZ?/m1@Q@C\?2Hgs5GV==88d*#5sG\Z$4A_n56
_`13VW7.BX%c+dWi/0oN;2eR5'g/AAD9^Lt[19;>dWIpVUbdK@XqE.eb,oc",;0=Z(ANkT1ET5$AjD
#P0QU:DFlOjG$(1@rB'K[bIrmrb.1cSC^k-T&5IVkP@IB/T5pXRIf<>\Au.I]@rYX2.)\ELQGJE=H!
RN1M[%o8ttX(2.YSe-tkmq*VcQFpmFh^=H3s("?"LdN%m(e)n]k@cCegchOMGMCbseAU%o7=pJl_"<
iWQ&CP'dc/P2]k&?Q&2f5nn8N8Yqf@U(3#;R-;t[luasg',_b92CmSP<B%,c3!>`E_KVG!t\R%?lU(
G%t`a'E&K'+r2jmclcGtrQ`cJU!TKg,V#asf$NrEFGiP4?e6.F9n%O.Ri20P$eZ3"V9`&m<A:!j:hg
Ba3!Hj&_>V?/m@*`""#h2DGJ-R,bnVUD\i_3QdCAm+4C=EsV<<*b%H#Ia9_5K6,EGA"H30#lhBWh_0
N"tJ+E6"h,N'H`)F-9bQn(aa>UT5M@!MX]Z=om.NUI?;<'$ML-Peb"+!/Te]$Nas@ph(\A"AMci/bu
D2K2"t\)B'KON-:5YGgAPIllt2^/8-AG_%0u(RY7D9aB2k;[HeCZa!NsXSFl%93$aW`Km=a,4YhA36
d0Cj\Zi4V;!&a:B'nW0"g#s<i%on1#t3Ei$>r$`-O>??X)(g@5CKDf(I>J_:V4S.=p"Vb'r2W?,Tq6
k"(r]qXLOREV*ff>0]s$pGPCLt6e-UGrS!f`p+Q"R$d!W(0d#3O0-8Cdhr.`s:?bZblt'MgHJ->W>9
i%#24t*MV;U):qDg5`(D]msBQXCcN<=u`?I4br@BER8p]KQ9!fCbWHGn4tY2oDR+8omI@lsa6(?>"Y
s84L?D$of][.XpB0L'rq;lJ$O`CAj2,-WSkY#Y@/rn!BAbTXoN^`;>tiLogC"Y0m+Hp4DjU<Rb_m")
g0R%mb2h)52g0n?jZ.1.E)-N_\[.WCMb\_1,ijfDrEj`aAJd;$H@6e<\f@ur)Cq@:+=-il-KpiB85h
=oM"idH[pj$c6+R\j9-ZcYC5bX`P)F2e%Oq.QVg'7fXUm"dYL0i$?$0C[M$8TF2f+gA?[<N2-i/RU:
'R9Ug[.Y]YfTTfm^!rXMamp#\@.^$rNT=n+!GfsJE8b*97-GLEfJCY4T!U:;Hp347BSQFW81u0d\3U
m(t=SS8uI_uURX:?WqhnAd@]*`Dg7XtVsW\d1&KdabfJTmsgE)"p)RKI2R@KeS]ORDGk?lTI8&b)^d
G>*Ym_.J5\r^`B7R[mIdT%@F,7?K;1e9P^V/l\<IifCB'CV9cjq#.OrXbNng+FppZTU@m\.gN<SX<g
;n_iWc6XoPR(;,D(#+5E2_c0R'`ND`?rm%>[!XTbbu>WWuJ3!e0]SPqo-,fcS]:^DkUZ^;EU1ZQORb
(E8r6C0O4epP<\br=NBl9I-q0^QM9q&pZfXpMIf^.iN@^Wgno;?7p>AhEpO=tcs%&2P&'O5*o8=%>h
+Y=7_O$1cR32RIpW2VFYqf!_X`HQUGP>XC:=CJ&+a@WGrOKOfgjh;H;)14-$#PG,?R8q?lU!tSYALM
NHh=pXL1^=d(GYgu1KP%r\6X2D1VBe=#')J&1_'nsc]iZ;<XJ<CjZT)o"EDmf_'8*k6TMj=u0&IP@>
dX)P0>?Jn"p/[3k*5D[qki<0d.(9_.,prK_]]VG9qbD"!-\0'A`gB/hTYMn!pUf<GBj>?7>p,M=fIk
R$SooS"q1'pF,3$WK/^?S9eG&k*ASsOM#;p8>#Z0jipY6T/i`IV?1$8$cek4u.2rQ&g$s?<]DMbIq&
H/G&j,%9O#u^$!;3P7ZhL_V>`mkf7I.?48K+ojlbFpFmTas\(5bP5K,NXHu%/d\c1\g:QLd?\KQs6d
JRJs,V:%8#G=[??p(i3B-i9=Fi)0c(NAmgCFfb6La6a3@s"Ef1ce"?X3?8ijeo7oR.iKKaK\nS@l2$
Q%FWAn]fC)?K"F#DL\);Q>H[/nX]I2mjcij#Gps8DCNH2H@R?CVN6fO.$t@BrIA-o+35c9O#g%B7k-
9">H4i6GMlH5i(eJCL$Sj@17h@lm*:%f;]?N+n#>P/0fH00Ei;(I,>'ecJ@-KB>+u"_f('N/"E"Bc^
B;<qAPE?"q%8/."Cl!+B*c$H+rrTJY4t2?f_2E<Z/A6aYe\p*FK>QhJ-MYX^tj!AH$k9u(Z7F7dWU(
eU#)>kmZ`54tn-oKu,I"Pi_dois8i\/Dn.f.fd&qqBXshiBMT7j6hqhtko<+8S>*Go+;M54kNZS\4E
>n%21/X-k]1=+dsDTMi>G\/nq@V_T*Ube[Jh9V\+>cSpG?@j.-<>09hVpGNGD<7$eYiI)BHeCC`cNn
&B2+VkRN(,FI;O7K\_8gC[N?0eq0LV_DDP^Y98DJjN:.3PqG$n76Il0.[(].XHs\[KA<J?#H71B@GT
=jm`$r01BcmXoh:*JX=@@um09f]Z+4@u5[,c[=k2#6boqlh4bQ0,7U2o\.p2[L2HH&Z3>Z?t[ac3>e
lPAd!.G%j=>8Z)U3B09nrL!)G_o<5sXVEfTHZ&L^hu5$(`HPf=cbhUS+.FFQ#SGt?BsI`%Dam./6&3
`tOiH?I<85U@K,PtBALbnd@;r3E+<+Jb8$*Xc:c;D=&]'`/sn*2E&/l5BVE#jW#<%@4FPY\-dn[D)G
YN&!;1\c)6VGC@mM9cs8ba**!<,e.K.H;3sYa#i-TA^"mX2.2Jr9/&o;orV(A*t%KZs7jW1hY+CeSU
taG^X0=t5sjH[LX8T=kX-"kG]0%9H1;)7Q2GK7VQ%f/ckNT+--`tnGf\JrbHVHpFe8][rK&'DI1:Sr
;gZ4i/9M3k.9fYBcTE:"je:t2@+g(n'nMp,@qp3cOA+"T!HW-*k6h@d1i6@t0ql)5HL"<6^kC?4;2`
G!LgX%h2LPUA/R#b5Gta.Yig\fC*!9eh*jh1eeb[il"P8(oUEA<[X'4'\+c&Lq`.9Y()F:c2MQ_S($
OH45kf)>Bajrj72gPm,2.]Q@cQ>K`2"8k?$EmTI%.M#V<_?6T2)bj!6]`CZ%1r^-Uf^C%7.`:7\STK
'W\lKJqM9WLWG)&M^j_tfEkqV763DCTh/ufHT1kmt^p?F4gK7q5#p?kJ]'FMXDenE[/Eh\]2mfSj9k
(2drS7Ko;q0=@cRP;pMo@&-nVLO]*tArq@khERe2h<c-t"l]*b08Sf1[kU)*#?%do9Pd$Y(_V+n'LM
0_\]04cUiO$:eH='Zdk#a'85=k.?Tfo4lmuP\]HKY"P@tA"BsqNbPTaPC-(i1':<Fi>k0a,t/Jk99:
BjagDNMPt&p-jDr/p/*ia)lO;dTiC^(_(4:s:eNDdQLCV&jriQ<G"6CX*k)3UEiY=]gn??W:dC&gpl
/<,V1WEI'O7uP0BT=o<gX;(ti@ltU]RY9AcKXE13[*;6H0:a1K7R'`aUKS=mBtO]):*SGmi"'G^9XI
1%;(;:.7c4dIJL`bhgd-U#`q*#gVOZ*TiL!)1.$O7=(dHU?*uLBbM2.`1L28f)]?pYC<^1%A-@*u5L
h:r\hZ6\`!:"5MACiI,"NJX6'-tsDX@kuRm]QX<)IlZi,85iC[0QY[a+noCl.I"46sG$@nGWW?leQ9
MQGue(;99#,qCM^<*ZUElaSkf&U;hV?hqhpb5<;Y&GEbCaC["u95FSnSK#UncJjrVFpu=A=X8NKKjf
&5Z#^hJS(WFjq5=\6OjZi;N%WP;K@IpYoU-6SEd(Oj6&`MMhY4a.p\qo(mb9n!OMr+VA5s;S8nR\mf
ilno>#KlS1g$0$5U6'RJ6-^!3K$Q_2BaMt-Ne1$oWg,jI'NR;XXQmC-3+Q.TOLJj*mCCAi'XN"e[h\
F>padh*r!dF\5kKP1]>@3Q7<D4HaCUKF7CesPsjmehA&>>l_.^oC?hl@-LDg=,u]++Qt7cVcWpSqf8
\^[pJWWQ(<6WHj$I::\0ptfHc>qAZo7s>6N7c=4+i*p1*D)XT/eih7WjZY,[bW8/[t@AYBLus6!3`@
WAX`@$f6)8nCbfDCLRkeO>\f-R[=m$9W@H".A3N%2APi"%EKIR")SVU8qP"0rc??K2%spF!A&b^i%F
%@[8>CQW@!ccV'W(kCRd93`6NY8ku8b@Cu]s*HK%:c_PNL#(8.dlTU:(l]<D)e,-9D3ZaomQV-/-$:
ge;Yaf*=UWS@:nB66OJb4r>AElRVM4-s+g'RBmWk.u5Pr2g+kdG:Lm7Itl7`jC7Xj0J5a:4kEK%lX\
Z8otN^1K$ldgD>.]VnmF,-A20CQbKiuJM'q<G$dXjHu6c\,o2^M)p2R#/cs8Ib`=&-m1=r3*C4L5WY
L+'@MU!uOU]s\1c!S_!P?ctp)uQ*;HMd[ba8tJEn.?>>'j#<a=@CAs0dSf\E:9&mFs?aQi+"<6L9)#
8l:OXc%MC0B>82!cU)pL`EQ^t<g&Y#cP'g+mpRX_]>s;G@MrAN^Phm%o;eo8`t34XX9G6lJq=?e5L^
`4Sd+rN"Xemh$E,bk0(L`LHIUZh&j^cI"KRKkcO:nJ$9'ZRRU?-(L?(5+WZc(-@qhl5Z:%&c0We;h2
49m'+fNt1>HhEA.*k3,.[2MQ#kPU=h,Juu!-AK4V/2pXI2fSA?L&t_5FKYo&f>Brkl<5!TcdAD"uO+
.5VC$h+;f'9IM_U)G&K&=KnsEj*_Rg&MYjgDHK$lC6X^J8(T\4r[DG'F:Q[5'#+6P'%%IOId2ao6hP
<?*'scY2(MHWE-T4$%*FV\8)CQ3>SLjko3L]cK`$4Q3-m"%BhJ,?]*]TXr:Xb=t\?!d-R]3.81ijkY
Nq7<?9l_]aPjSeR0Q[UrEUWP%m2OpOL+CP+kHZu?:S9PI"9&<<Ps@J:X,T]AA,Yc!T]Y$RDm9XX=69
uX%QFJe\IEC4)+T\Apk5+#4)2Ji;h/l@oooFG]=`X893uXbD<BD##O[jm1:OZ-QkkSApF\&3YJdO#^
2&)l^KCrUhjfar7c%.YEaKODi.B@Z$l3^Y(^bEp+e$f+j<GbGrguPBV!&2::Y`d'\(u42`cVSA[r[u
Wrg89R98jJaX,@;;Fql>[<%EibWKm^MI:cX"/<uO'om#=P76n1MMlsB8*RCTtP!b'``[(Y\B8uR_]&
%sfFm9,h5&Ys%pW?T##CI"I/iEsoF2Vbmm%q%HCTPI-fpaGkhCh3CXW`Y]Vbi\Y<2VnY<gUd;WjP+o
R(29X%6+E7Q]"CC"%A>pi:gA)ScNaeBmfLZ'o["0'nkK.'6<um$"jW6e:@-RY15:=grsZ+OhnHd-#,
JP,8)TCG-KpZ'.Zm8aV0Lo[($V?r5h``EqZc,bDdSk'*,e.Nd493lSW8YJ@*o-SjHSlRBuM?*7X)bc
[R$?e:d8m:`OjKZh/ZrPOf4sjE#M3ZZ)(u%JqtS5q6(Tm/.Z@_m:]3k@=?gXaYh=!C/W6Lq2+S,qXW
aoH`XhqIb\Ng7NL=+s74f2(dKA;PVJk'msB53Eg(l1p@B@[8a0:@u7)LA+/#h7N]#+eXfq(.>!>D3-
u:qEp[%O.BKU@XX*;-5s:g9$Sd@S"07(^kd^`]K:Y$K*I$;DH=0V)"^oDiNs(7?RYMSR(g!>!M\]c*
fJ*t'5mP$GpgLK*kSuLH0O]!P"Z\HYR\c\Mn7gU7;:a.h3@6FT='CP,pN8)Z_O(@+Z:/7"bZM"]!:i
#!L5C2hXSE\9k?PrPN3D1pS29#k:N'89s.as!`&M/M0RS>Q(',M2#.:Q1loaJ0fErJn[T[A%R[>\E>
i\/P(cC^[2m=iKIqmY+K@dJOF5XUD[D_TShi('UYrE.Y%mlD"^cl.ti+5giHEGEj2M.4H`BK4EB1iL
`CBF7o?f,!-*e!\.s15it0!U6BQ>:2TiWc0IgT^cR1p&@WT7"^^54F+61^B$Qb_I.q=GV7BAYCf&%"
Kt`S"&SCQTbIblZJN=OcKOHg!B!A,KN?6T6k*3]$/F]pl8dERKmE0C9IITL2REjf64=q]WT,MV$c&p
l8_lXN!)P%RD'@e^efL!4L&c27>E5@('.4I`nCdX"KtsP"YK/;eI9e&Z4E=p.!V/Oc#p<GPm+[2rh"
91@b9'rOodF+'78_jdWC_l>6=n6fP'fqPaB(LSGY,+?!&&mm+9U#VZkRaf?,-h2mp%#i#2m@@I8:Lc
0Ja:qU>HR.9a#&4n?Z=Vg5a'g5R3cF+s-q+h(5\L_[Z#WiMDBMjOeOPIAPm+N<M9<R5h#^./Ug>m)9
Qi2"mY'.p-a>m]-n6!/US?eeTH2#nZU1V7Tu.A/Oa7\S>)49$(M^m^2'EQkQ#)/NBS"0lc]rR:uM^L
uY[P8/Y^-(5[c.+0G-ZP?_J*n7#ZQS.Y`kaGE^OW)=]^_22o'B/CVD)TpD20Z)En33;D2.(!Jq-]Lq
)Zbi$@Ubteh1cj$qTpSu7#E>Z>^A8[EV=CQH1CAb\iO5\#_61\cMdG?D]L@<[q^]0-!3As*<f+ELcj
G&m>CsOdWuT0$_`qHYBF\!h%l"&HaZ9dJ*6gk51]SZ[JuRa7l*;gh`m?Ej]RN)j/S<]jS-&-[;23'i
mGc+]q+@AJ@ah9f*Lep3:6sP3O(-s^._EE@d?p9Br'nIl6"<:cdl?9(<4Jkf2siDcSVVTd)]oY1P=.
el4NZ5%o\O?DJ+N("VtUA=DtT8rQG*J@G3_)UhQDTU@?i<.=sWsc'VYWQ8Q$KX0*;BbHlbYO^dHBBe
HfRW9l5]TZ'&56([W-k!a@jDKKrjnq[.Z>4#Z'm6r*GcW"8(OWU'r>nF<:(^rP(\rjk8l!=D1%SH80
qZ-9pmYmWc\ht&j8$F:*Id@ZjmSciY*+\W/2'LF@[mUK67UD,V@^R0c#2bIHE39h9?(+ou\ObWPk0d
R/=q(/\FoAI_[:h1_+4^fr1)gIq%tdmbJe@/g3!HLl!q$77AfrYl;1ohfP51+%FM'O!E=DqSllFZ>[
6h4.kR@?&BY\==j*M9B0UoK3g:h\<G1Eq+Z6a%ZB\Z)#f;Q(cne>q(QFsqho>6l+W4;oB*GqP%J4Ue
+Z?n/GdfS``:g](cLF>[?kP&*bn,_1^#^6-62E@1`hY"$qmI#\PKL8m9bYdP3D<X'J0#90f,*C./Cg
uP6c\1$[lm:-NH(cqoJdeqqo$n!&!rarCXolRraf9dB^a\C\)ju0kJ0!Ugq;\'Y1te6bU"11)-9l:?
."GFoh:RWd(PHZE;]AG.XD."[;MiV>-s:u62?_7/VYWD%@o2)89:>#2H<5,u>puC0LWQPh[c?D+V:s
L6Ah[XY`e#dX-EITcdE!<'&.jDbC30Ti&VGV[GmQ\k<eags]ldE2+!B@jr*q;YbcsJ_nBDj<cG?9nP
P`aeCp*H$!GlP-C->%<8_8RXi#,fc'.k^=cM=qO(Hm@3qb1GO%W'0XbYKj#"$">/YS,W;Xoqq1eriB
3!_a:0eX1ES],KlPGZdqCni]Jd*K(3Tdmrl^Q\:G\rU8=<?i'\7"j(h/RdS0i4n-5hUUh2nWG'Q4i/
H+8ghrp2eCqHg--D;NnGB/<mVa[Wg(l@I^]ANEa#UNEdhEu-?/Klu>9Se35[P^%Reo(1[]O>q4A/AQ
<:pY(Mq4]I__aF"@0UH`YXO'FG<\;[lWYU4lS"S(R#/c\mjbWk`LeR*_HJL%p77qgBAkk;UTJ7*]#\
VQ*1#[pTND]sH!@![hLSMah!ffX=^)cas",D8/-5%%4YG">"XR[hbJfAUG<L/*8hOlGC;bZ"R[TjZ:
e1)s?^j?UV5i*KXa4?mDt+rr*frmEO"Q#-F(S#Yi2tZo$:T"93_U#,"IDjfFUfEmJ6MWN3U",FiTD>
YgIoaB$;A[MKkE/j..&7KMf=(Y%L^5qF(@E-NM\>T$!;W,L[8*GIHHVKbO)%dUX]uh5o\:]@UY[<SM
6F2T08')8R(rdn[ge*T'l^B4L@5q-,A`ARbJ/lBn>2Ye:aT4/l0bfA%-\IP2q6+4ui>XfMGrTqU]pM
!hcUugbYo#rl,mq/2@hRs/s!%]'B.m=KR='m'g<L6ME>BN7"qs?(7f-&=Blr>3l9>#Cttm\K_LalF9
=Ch!P9krLL9`,JA#q"Wt^(U)#HQo+q))Eh.!^rlsA\k/Cu<g`3Al?IB0tN7)0en'`\E6'tm*Nhp0r"
S;u`6U<m8DV!P5GA8RTAdsQ-c:9H-A1dpJ]k;])G;YAJ6Ca=Tpon$gp<,[J$0at//LK^a2r6UC:fgr
k=Kr?TV[!#A9;#lnLJ67!d@GL<H%dPR8l:k#n%Er8%V'=&X:Gm[D3!#q/ZXR*=#LY)CNIH#^]^kM_;
(gI`1G7IRG9#snDJ.?%s<G`i6H^o!OKa8'JLa\N(2da=NJpg!/j+F.fh?.W(YAU`4WmH,?T!2Y&'!0
nO2l+g3#tH1[&\WG1gG8WR\`/@uY2.I6=.Ja&;/Wf`,s:,3Vh!etu4ZA>o994BV<Ne[u)OQj.3haI4
@TE8H*ErAu^0SEM,EmR3a]1O)u-FcJ,2,n.g*@(R\gf3A[ZWbho2Fos)e505Og"^Q_2g(KWmLh!n*b
W[lI;G5/lV?q!cs+di[mJrc2FX$D]gp@uc!)B.8%/ZCnk@")?(JGkk>M@t_nK#09Y%;i^5W?\;[$\m
D@ijbp?U(,&,I4'JC^qtHpEhlk^8>bjdhHg4AL6KJj4lEH=Sd7PXW:iZPpc#Wp<1dKr56D_5C?WQ:k
(P?MtVufLe-XAMdq>CgnibD^O>Q^:eT4)!$PtL)A-+YdW!mTUi?hq[ZXRtjs2K*N+iRh[7"bQ.I9D(
_Ld<kSNTA>&i2'U$\5t;19FJ3OH$irO>=?b1Xl;r3AkPfAj)A8]VtLDNAYf6MbS:c@#ROs1pn*9e%5
=bO\GK!7UY\j5XcfV@u0'es%>Vj7`!4B0ec<XGJ(s`\^jBhEX(XN;3`cB3?A@jf#VI/O>c?1m&%')F
N`a=r?;[F?*6QLd="Pb[?NS:6*84"(.Rlh0Zf@V^b:35bHq(JL4]7FM*1s6,;?CM=Vp4_6YPi'+fM6
5j[T35I>Ca61AIg_&T+OC"=$R9p+^dd;E!&I!b;jC\W=!^#0bq%^nl>Aq_!phQNFSqXcN<0ml_^!3e
tH$V'=lRJpJ$]2'6NrLESnScpORr3a/`k">EINmRu\GpZ8C3I.PUr6:dn9T6q_hp#mpR4+t1uPI1EP
-?npLEO.8O+6IWY5C0C+b^p]O9k.^K-Wt5j[s<tljT$aQKs'+Y*n/X^.p'/oq%fhF;^G31\/P,skOL
80nqX;>Tmsi'4k30k/R18fH!:U-"ZsuW;nsD/cX"-FSpPW\lK6[S>DgagK:Pa%7.]U,79tM\&8H'5g
IaE\FOS&EWf-t#Qo<M*9^d`j]=6-&*C!k/\%%\T3D1]3)sq$*n$67gO>k63<a6S9Z.3Y`2nBb6Qi3K
(c8:6eO(,\dY"\f4-'PE?Ml(QbMaRr:^TgYN'r30MlMB`QlC109Rp+Zm8t8fpf]NH_-5u:%?o"<&Kf
V_:3&Wpbh.l%Xo4MRE>F,Z1-3t$V]C3I\(*Nm'bS!qIQ2l"4ZRRR02CO*iFSa]ng3i>+)5fc<XDP%B
g%SdXA4e.F9->nZ2'Q3nSC]5Gn>Wt9Z#;o*/\B]\V2RCZ;H,Vc:e7fHiN]9T*Khs<$u[m/+LYD&ij%
"gNfAd+4RgKB$;`+SB5m$!P2eafi1Rp+$?&jkmq@;?bI(LT'ksT^0GgR_WM]-pbjdFOCb<SOEc:LIU
6^h]*Rjmh2.B:LS%lY/1q`uRS-u^r0hft[336XB-;4<WV.t&e*m"gis*aP")e#;d]lGC.cVk^18][h
FDc(IN;idL;2O[/+:lAs\U@go?DXL2d0gTk]fpl4PZPV7;E[We0iI;*fVj\J7(eDOgEh!5,e3"?(Xa
0@8#*!8u^]+($j(Kn,E5N,D9PQUC(U1AZ,j^.kNiX2cQX(I%?cOgQQG1AIU/;TZ!5/htAV;`Wep%Z4
LJ9d>J=<6Ki6HYfb&aGpopPR!D<?$daL>h]!dlnWa7p);;?V%'/%PdS_FG@q!VFVgZn1ZTcP^[</(.
uZd27c*KgQP^9>oDe65BTFC[Pq@?nq`V0m2Sn+Mm_r:tQ!D]Y3/2iZj80#?i7cZ&^ZB9JC('U<pp^C
95Jm$"h)_@?LV?MoF]&^`J37df!QskC1e)pK9t0-uGjUiIDC]X=Y$DY"pkY51q*^Q-%R`i'&a:h\#)
D^5gV'mdmSj1,U,NftG=6=u2-rRZDP>!V-hU]Cno)W')(ebNME%A:pYVF]/JH]:8Ds`u_i:LCt0DX^
.if("3-p*b.n9(0]\o[@k#J$+Qhcj^UP=Ad(`9?[88*i/kb"*+EabbY)`fHuUfiq*'_\Cr!bL5\I5Z
'Di'j1/D&TfC9idCRNo+P5a*netL'LJ6C-GY!&-kgjh2%o???tn\[8uk;>pSXUGaeW,<+4*O96m#(%
`-"OuRr=u@m`&eXo@RQ7#tB:n@'W`H1FpW%3\!;g"M'R^+?,@&d7gc;\Q%/7*JB_RM?8P<:uk-B3H^
&Y8g$9g8u>"R.C@DH9]g>@t%MqgehfVTt;*X:$B*%`YFd>_1uR[0Q*2PQ&#B/K7Wi[C6Qp'?tMRPfe
O)ZtHgZDkS4\Z)Vp$ta!Da%M"0i!u^;I]#%LDGFt6A;mT=5TY7RFH$;4k?\/Z6Pc*C2"l4G^Z5oYO`
<:f!3V=,,AF1(+?tY>C:i+EBeZbY"Lplp/cn/(-c'tIC%,%M2I\s=Z858B-FF'?R_-_M=;_*_m_dXk
s7sB2$akEG!YAEoD5#V8D-u,NQD3tWFfkr2C)NNTr99]J]$X"I6a;mCOQpkkT[5l.3MV*F_C(JjimA
PC?iVC$I&U1g$YTPf9Es,,>%?"I1ukcFX,L?GejA%YEU83.TnT'cct\Qi[0HNj;V>`YDMlDg9%a\dE
#ab]N)j(Ar7h99pXl[9#JeV@$ktog2\3En3Ee6^:P@j:Shjlm\'HoG'S]]lNm181#0JQUZNB?*Uuqd
.o`b&s`Dim'E5U#3V>kD>;4H"OA$)!r-eY4KBjt\Y2.:#0hCoAXkeAQ,c2.?_?k(I9XKZZfFD/.;RQ
5F.>neu>l3//sE+J(5;O$KN5i(@f(jS;6,<)9.8-HKdP]OBLko4J]G%e1F=_SsPgZgtbZ,HL^Omu*G
A+N7A+L)h%eApU2!IWtc)rV8L>2pJe&A_/5"-Ve_'%8mk\iL[<%)gU7$_U:tIWR!DOrVen0,t>Oh=D
rN*<PL<`5h#clM'>_k2,;@D7%^\dqBhM(Ld<Li'\B37kGs#06@&?"F6S3/qCL3<d-a)L6Vi6p`Ar4#
U_t@g0-=Q(q440k4`N)680btr@DW"0fZ>c.m+T?aEp\Rg)T3#%8uKnhbl,pS4]!Qq^MEYJf$C_fk@.
?2N>E;U6caQ>+fFKA,3i@ji8Kr%/*U:RZ+:ZqR>1?N5$Wc[$\mTcL$&Sh08^ahZh;MPa^(j4TL9uM.
LZI%q@Hc&>8JBZkF\Ej8=+L<kg+l*\/kn[+_Gbf@D3^V)`iY"'fVEcS5DH!Lg9Q@c))nNS%KJHTh+S
I2#Xb/5f?$Lm]Q1cUE44R6/%.7N7n,NP1#Sm.#41KVaob=Ecb]iKbU[V9(pmF.9GB5[]#uU!V12Ht[
9Flj?[H\b@tlcs1?OjODbKAkSAGTQGbb:a)K4s#gF$]N/kF&IV.^Q8ApSI:iC:p,lYcS9g/u4mMAa+
(JoDh9`6;?F&'s[*_>^YTFV5=u$_&mKaN7qTU<uS#m!L-TZ@.b3%VG&F93fgIV_VJ@JXAW3+U!1Ua=
UH"gWm+J7Ci%`o;gRUU>o6W.1h]Vf6cX15l%568te+8SGGSM*%1SHhb*AkcclDM$Z/WPmG+nL(Zf%4
pN%0Qjj<]D4C@6oRW"Z+[=5Tk9sV,r@K]++j$L3bIJ2Bdk(V6C(7b1B2+ioF0SRds#VJ4kGc[]?s(e
D8<lG8a,B@'`FkV!3LduGKhGU](ouI:&5"#6Wo$7%I.0\YDkHoBF+RG!!<3'S5(72F@&b'!!!!j78?
7R6=>B
ASCII85End
End
