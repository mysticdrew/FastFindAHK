#SingleInstance, Force
#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

;get things started!
global FF := new FastFind()

/*
	#cs ----------------------------------------------------------------------------
	FastFind Version: 2.2
	Author:         	FastFrench
	Some Wrappers:		frank10
	AutoIt Version: 3.3.8.1
	Modified for AutoHotkey: Mysticdrew
	Script Function:
	All FastFind.dll wrapper functions.
	This dll provides optimized screen processing. All actions implies at least 2 dll calls : one to copy the screen data into memory, and a second to make specific action.
	This way, you can make several actions even faster when they apply to the same screen data.
	
	Functions exported in FastFind.dll 1.8 are :
	
	SnapShot (Makes captures of the screen, a Window - partial or full - into memory, required before using any of the following.)
	
	ColorPixelSearch (Search the closest pixel with a given color)
	ColorCount (Count how many pixels with a given color exist in the SnapShot.)
	
	HasChanged (Says if two snapshots are exactly the same or not. Usefull to check if some changes occured in a given area. )
	LocalizeChanges (Same has HasChanged, but returns precisely the smallest rectangle that includes all the changes, and the number of pixels that are different).
	
	GetPixel (Gives the color of a pixel in the SnapShot. Much faster than PixelGetColor if you use this a lot.)
	
	AddColor
	RemoveColor (Those 3 functions allow management of a list of colors, instead of using only one)
	ResetColors (Tou can have up to 1024 colors active in the list)
	
	AddExcludedArea (Those functions add exceptions in the processing of screen areas, with rectangles that are ignored)
	ResetExcludedAreas (You can have up to 1024 areas in the list)
	IsExcluded
	
	ColorsSearch (Close to ColorSearch, except that instead of a single color, all colors of the current list are in use)
	ColorsPixelSearch (Similar to ColorPixelSearch, except that instead of a single color, all colors of the current list are in use)
	
	ColorSearch (it's the most versatile and powerful function (in 1.3) : you can, at the same time, check for as many colors as you want,
	with possibly a "ShadeVariation",  multiple subareas to ignore... will Find the closest spot with a all specified criteria.
	The spot is a square area of NxN pixels with at least P pixels that are as close as allowed by ShadeVariation
	from any of the colors in the list).
	
	ProgressiveSearch (new with 1.4 : similar to ColorSearch, except that if the "ideal" spot can't be found, can still search for the best spot available).
	
	GetLastErrorMsg
	FFVersion
	
	-- New in version 1.6
	SaveBMP
	SaveJPG
	GetLastFileSuffix
	
	KeepChanges
	KeepColor
	
	-- New in version 1.7
	DrawSnapShot
	FFSetPixel
	
	DuplicateSnapShot
	GetRawData
	
	-- New in version 2.0
	
	Function with an additionnal parameter (ShadeVariation) :
	KeepChanges
	LocalizeChanges
	HasChanged
	
	New functions :
	DrawSnapShotXY (same as DrawSnapShot, with specific top-left position for drawing).
	ComputeMeanValues (Gives mean Red, Green and Blue values)
	ApplyFilterOnSnapShot (apply a AND filter on each pixels in the SnapShot)
	FFGetRawData (gets direct access to all pixel data of a ScreenShot)
	
	Bug fix :
	FFColorCount with ShadeVariation
	
	-- 2.2
	
	Detects more error patterns (wrong coordinates)
	
	#ce ----------------------------------------------------------------------------
*/

Class FastFind {
	FFDefaultSnapShot := 0 ; Default SnapShot Nb
	FFDefautDebugMode := "0x00;0xE7" ; See below to the meaning of this value. To remove all debug features (file traces, graphical feedback..., use 0 here)
	
	; System global variables ** do not change them **
	FFDllHandle := -1
	FFLastSnap := 0
	FFNbSnapMax := 50
	FFLastSnapStatus := [FFNbSnapMax] ; array used to automatically make a SnapShot when needed
	DLL_NAME := "FastFind64.dll"
	LastFileNameParam := ""
	
	__New() {
		FFDllHandle := DllCall("LoadLibrary", "Str", "FastFind64.dll", "Ptr") 
		this.FFSetDebugMode(FFDefautDebugMode)
	}
	
	CloseFFDll() {
		if (FFDllHandle != -1) {
			DllCall("FreeLibrary", "Ptr", FFDllHandle)
		}
	}
	
	; Determines the debugging mode.
	; ------------------------------------------------- --------------------
	; The 4 bits determine the channel debugging enabled, they have the following meanings:
	; 0x00 = no debug
	; 0x01 = Information sent to the console (RequireAdmin)
	; 0x02 = debug information sent to a file (trace.txt)
	; 0x04 = Graphic display of points / areas identified
	; 0x08 = Display MessageBox (blocking)
	; Note that in case of error, a MessageBox is displayed in the DLL if DebugMode> 0
	
	; The following 4 bits are used to filter based on the origin of the debug message
	; 0x0010 / / Excludes internal traces of the DLL
	; 0x0020 / / Excludes detailed internal traces of the DLL
	; 0x0040 / / Excludes external traces (those of the application)
	; 0x0080 / / Error message (priority)
	;
	; Errors (serious) are displayed on all available channels (file, console and MessageBox) if $ DebugMode> 0
	;
	; Proto C function: void SetDebugMode (int NewMode)
	FFSetDebugMode(DebugMode) {
		DllCall(FFDllHandle, "none", "SetDebugMode", "int", DebugMode)
	}
	
	; The DLL also exposes its debugging functions, allowing the AutoIt application share same traces
	FFTrace(DebugString) {
		DllCall(FFDllHandle, "none", "DebugTrace", "str", DebugString)
	}
	
	
	; This function allows you to handle errors (the text appears in the logfile, the console and a MessageBox if $ DebugMode> 0)
	FFTraceError(DebugString) {
		DllCall(FFDllHandle, "none", "DebugError", "str", DebugString)
	}
	
	; Sets the current window to use
	; -----------------------------------
	; By default, the entire screen is used. You can select a particular window. By default, we will always use the last Window set.
	; If $WindowsHandle = 0, the entire screen : GetDesktopWindow ()
	; If ClientOnly = True, then only the client part of the Window will be capturable, and coordinates will be relative to top-left
	; corner of the client area (client area is the full Window except title bar, possibly menu area, borders...)
	; If ClientOnly = False, then the full Window will be used.
	;
	; Proto C function: void SetHWnd(HWND NewWindowHandle, bool bClientArea);
	FFSetWnd(WindowHandle, ClientOnly = True) {
		DllCall($FFDllHandle, "none", "SetHWnd", "HWND", WindowHandle, "BOOLEAN", ClientOnly)
	}
	
	; Choose the Default SnapShot that will by used in the next operations. This avoid to specify the number of the SnapShot every time when you always work on the same
	FFSetDefaultSnapShot(NewSnapShot) {
		FFDefaultSnapShot := NewSnapShot
	}
	
		; Managing the list of colors
	; ================================
	; When a parameter is proposed Dane Color function, the value -1 means that all colors in the list are taken into account
	
	; Add one or more colors in the list maintained by FastFind
	; Proto C function: int addColor (int newColor)
	FFAddColor(NewColor) {
		local res
		if (isArray(NewColor)) {
			for i, color in NewColor {
				res := DllCall(FFDllHandle, "int", "AddColor", "int", Color)
			}
		} else {
			res := DllCall(FFDllHandle, "int", "AddColor", "int", NewColor)
		}
		
		if(isArray(res)) {
			return res[0]
		} 
		
		return res
	}
	
	; Remove a color (if any) from the list of colors
	;
	; Proto C function: int RemoveColor (int newColor)
	FFRemoveColor(OldColor) {
		local $res := DllCall(FFDllHandle, "int", "RemoveColor", "int", OldColor)
		if(isArray(res)) {
			return res[0]
		} 
		return res
	}
	
	; Totally Empty the list of colors
	;
	; Proto C function: int ResetColors ()
	FFResetColors() {
		DllCall(FFDllHandle, "none", "ResetColors")
	}
	
	; Exclusion areas management
	; ==========================
	; Exclusion zones can restrict searches with all functions
	; Search
	; It is possible to have up to 1024 rectangles of exclusion, thereby removing precisely
	; Any search area. For example, with flash, the mouse cursor will usually appears on the snapshots
	; (unlike cursors managed by Windows API). You can use an Exclusion rectangle established according to the position
	; of the mouse so the cursor does not affect the Search results.
	;
	; Adds an exclusion zone
	;
	; Proto C function: void WINAPI AddExcludedArea (int x1, int y1, int x2, int y2)
	FFAddExcludedArea(x1, y1, x2, y2) {
		local res := DllCall(FFDllHandle, "int", "AddExcludedArea", "int", x1, "int", y1, "int", x2, "int", y2)
		if(isArray(res)) {
			return res[0]
		} 
		return res
	}
	
	; Clears the list of all zones
	;
	; Proto C function: void WINAPI ResetExcludedAreas()
	FFResetExcludedAreas() {
		DllCall(FFDllHandle, "none", "ResetExcludedAreas")
	}
	
	; Through the list of exclusion zones to determine if the point passed as a parameter is excluded or not.
	;
	; Proto C function: bool WINAPI IsExcluded(int x, int y, HWND hWnd)
	FFIsExcluded(x, y, hWnd) {
		local res := DllCall(FFDllHandle, "BOOLEAN", "IsExcluded", "int", x, "int", y, "HWND", hWnd)
		if(isArray(res)) {
			return res[0]
		} 
		return res
	}
	
	; FFSnapShot Function - This function allows you to make a copy of the screen, window or only a part in memory
	; - All other functions of FF running from memory, it should first run FFSnapShot (either explicitly or implicitly as designed within this wrapper)
	; It is possible to perform several different catches and work on any thereafter.
	;
	; Input:
	; The area to capture (in coordinates relative to the boundaries of the window if a window handle nonzero indicated) [optional, the entire screen by default]
	; If the area indicated is 0,0,0,0 then this is the entire window (or screen) to be captured
	; The ID to use SnapShot (optional, default to the last used, 0 initially)
	; And a window handle [optional, the same screen as the previous time by default. Initially, the entire screen.]
	;
	; Warning: Graphic data is stored in memory, the use of this feature consumes memory. It takes about 1.8 MB of RAM to capture 800x600.
	; Therefore it should preferably always reuse the same No. SnapShot. Nevertheless, it is possible to store up to 1024 screens.
	;
	; Return Values: If unsuccessful, returns 0 and sets @Error.
	; If successful, returns 1
	; Proto C function: int WINAPI SnapShot(int aLeft, int aTop, int aRight, int aBottom, int NoSnapShot)
	FFSnapShot(aLeft := 0, aTop := 0, aRight := 0, aBottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local res
		if (!NoSnapShot) {
			NoSnapShot := FFDefaultSnapShot
		}
		
		if (WindowHandle != -1) {
			this.FFSetWnd(WindowHandle)
		} 
		
		FFDefaultSnapShot = NoSnapShot ; Store the number of the SnapShot used, it will remain the default SnapShop for the next calls
		res := DllCall(FFDllHandle, "int", "SnapShot", "int", aLeft, "int", aTop, "int", aRight, "int", aBottom, "int", NoSnapShot)
		
		If (((!isArray(res)) && (res = 0)) || res[0] = 0) {
			return False
		}
		
		FFLastSnapStatus[NoSnapShot] := 1
		FFLastSnap := NoSnapShot
		return True
	}
	
	; Internal Function, don't use it directly
	SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle) { 
		;If you impose a new capture or if SnapShot is valid, this effect will be effective for N °
		if (ForceNewSnap || FFLastSnapStatus[NoSnapShot] != 1) { 
			return this.FFSnapShot(Left, Top, Right, Bottom, NoSnapShot, WindowHandle)
		} 
		return True
	}
	
	; FFNearestPixel Function - This function works like PixelSearch, except that instead of returning the first pixel found,
	; it returns the closest from a given position (PosX,PosY)
	; Return Values: If unsuccessful, returns 0 and sets @Error.
	; If successful, an array of 2 elements:
	;		[0] : X coordinate of the pixel found the nearest
	; 		[1] : Y coordinate of the pixel
	; Example: To find the pixel with color 0x00AB0C45 as close as possible from 500, 500 in full screen
	;  Res = FFNearestPixel(500, 500, 0x00AB0C45)
	; If Not @Error Then MsgBox (0, "Resource", "Found in" & PosX & "," & PosY)
	;
	; Proto C function: int WINAPI ColorPixelSearch(int &XRef, int &YRef, int ColorToFind, int NoSnapShot)
	FFNearestPixel(PosX, PosY, Color, ForceNewSnap := true, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local result
		local coordResult
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			Return False
		}
		result = DllCall(FFDllHandle, "int", "ColorPixelSearch", "int*", PosX, "int*",PosY, "int", Color, "int", NoSnapShot)
		If (!isArray(result) || result[0] != 1) {
			Return False
		}
		coordResult[2] := [result[1], result[2]] ; PosX, PosY
		return coordResult
	}
	
	; FFNearestSpot Function - This feature allows you to find, among all the area (or "spots") containing a minimum number of pixels
	; a given color, the one that is closest to a reference point.
	; Return Values: If unsuccessful, returns 0 and sets @Error.
	; If successful, an array of 3 elements: [0] : X coordinate of the nearest spot   [1] : Y coordinate of the nearest spot   [2] : Number of pixels found in the nearest spot
	; For example, suppose you want to detect a blue circle (Color = 0x000000FF) partially obscured, diameter 32 pixels (say with at least 45 pixels having the right color)
	; and the closest possible to the position x = 198 and y = 543, in a full screen, so the function is called as follows:
	; FFNearestSpot Res = (32, 45, 198, 543, 0x000000FF)
	; If Not @Error Then MsgBox (0, "Blue Circle", "The blue circle closest to the position 198, 543 is at "&PosX&","&PosY&@LF&" and contains "&NbPixel&" blue pixels")
	;
	; Proto C function: int WINAPI GenericColorSearch(int SizeSearch, int &NbMatchMin, int &XRef, int &YRef, int ColorToFind, int ShadeVariation, int NoSnapShot)
	FFNearestSpot(SizeSearch, NbPixel, PosX, PosY, Color, ShadeVariation := 0, ForceNewSnap := true, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local result
		local coordResult
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			Return False
		}
		
		result = DllCall(FFDllHandle, "int", "GenericColorSearch", "int", SizeSearch, "int*", NbPixel, "int*", PosX, "int*",PosY, "int", Color, "int", ShadeVariation, "int", NoSnapShot)
		If (!isArray(result) || result[0] != 1) {
			Return False
		}
		coordResult[3] := [Result[3], Result[4], Result[2]] ; PosX, PoxY, Nombre de pixels
		return coordResult
	}
	
	; FFBestSpot Function - This feature is similar to FFNearestSpot, but even more powerful.
	;    Suppose for instance that you want to find a spot with ideally 200 blue pixels in a 50x50 area, but some of those pixels may be covered, and also for transparency reasons, the color may be a bit different.
	;    So, if it can't find a spot with 200 pure blue pixels, you could accept "lower" results, like only 120 blue pixels minimum, and - if enough pure blue pixels can't be found - try to find something close enough
	;    with ShadeVariation.
	;    FFBestSpot will do that all for you.
	;    Here is how it works :
	;      Only one additionnal parameters compared to FFNearestSpot : you give the minimum acceptable number of pixels to find, and then the "optimal" number. All other parameters are the same, with same meaning.
	;      First, FFBestSpot will try to find if any spot exist with at least the optimal number of pixels and pure color (or colors). If yes, then it return the one that as the shorter distance with PoxX/PosY
	;     Otherwise, it will try to find the spots that has the better number of pixels in the pure Color (or colors). If it can find a spot with at least the minimum acceptable number of pixels, then it returns this spot.
	;     Otherwise, it will try again the two same searches, but now with ShadeVariation as set in the parameter (if this parameter is not 0)
	;     If no proper spot can be found, returns 0 in the first element of the array and set @Error=1.
	;
	; Proto C function: int WINAPI ProgressiveSearch(int SizeSearch, int &NbMatchMin, int NbMatchMax, int &XRef, int &YRef, int ColorToFind/*-1 if several colors*/, int ShadeVariation, int NoSnapShot)
	FFBestSpot(SizeSearch, MinNbPixel, OptNbPixel, PosX, PosY, Color, ShadeVariation := 0, ForceNewSnap := true, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local result
		local coordResult
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			Return False
		}
		result = DllCall(FFDllHandle, "int", "ProgressiveSearch", "int", SizeSearch, "int*", MinNbPixel, "int", OptNbPixel, "int*", PosX, "int*",PosY, "int", Color, "int", ShadeVariation, "int", NoSnapShot)
		If (!isArray(result) || result[0] != 1) {
			Return False
		}
		coordResult[3] := [Result[4], Result[5], Result[2]] ; PosX, PoxY, Nombre de pixels
		return coordResult
	}
	
	; FFColorCount Function - This function counts the number of pixels with the specified color, exact or approximate (ShadeVariation).
	;
	; Proto C  : int WINAPI ColorCount(int ColorToFind, int NoSnapShot, int ShadeVariation) {
	FFColorCount(ColorToCount,  ShadeVariation := 0, ForceNewSnap := true, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local result
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			Return False
		}
		
		result = DllCall(FFDllHandle, "int", "ColorCount", "int", ColorToCount, "int", NoSnapShot, "int", ShadeVariation)
		If (!isArray(Result)) { 
			Return False
		}
		Return result[0]
	}
	
	; FFIsDifferent Function - This function compares two SnapShots of the same window and return whether they have different or not .
	; modified by frank10
	; Proto C : int WINAPI HasChanged(int NoSnapShot, int NoSnapShot2, int ShadeVariation);  // ** Changed in version 2.0 : ShadeVariation added **
	FFIsDifferent(NoSnapShot1, NoSnapShot2, ShadeVariation := 0) {
		result = DllCall(FFDllHandle, "int", "HasChanged", "int", NoSnapShot1, "int", NoSnapShot2, "int", ShadeVariation)
		If (!isArray(Result)) { 
			Return False 
		}
		Return result[0]
	}
	
	; FFLocalizeChanges Function - This function compares two SnapShots and specifies the number of different pixels and the smallest rectangle containing all changes.
	; modified by frank10
	; If unsuccessful, @Error = 1 and returns 0
	; In case of differences, returns an array of 5 elements thus formed:
	; [0]: left edge of the rectangle
	; [1]: upper edge of the rectangle
	; [2]: right edge of the rectangle
	; [3]: lower edge of the rectangle
	; [4]: Number of pixels that changed
	; Proto C : int WINAPI LocalizeChanges(int NoSnapShot, int NoSnapShot2, int &xMin, int &yMin, int &xMax, int &yMax, int &nbFound, int ShadeVariation);  // ** Changed in version 2.0 : ShadeVariation added **
	FFLocalizeChanges(NoSnapShot1, NoSnapShot2, ShadeVariation := 0) {
		local TabRes
		local Result := DllCall(FFDllHandle, "int", "LocalizeChanges", "int", NoSnapShot1, "int", NoSnapShot2, "int*", 0, "int*", 0, "int*", 0, "int*", 0, "int*", 0, "int" , ShadeVariation )
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		TabRes[5] := [Result[3], Result[4], Result[5], Result[6], Result[7]]
		Return TabRes
	}
	
	; FFGetPixel Function - Cette fonction est close to PixelGetColor, except it works on a SnapShot.
	;                       In order to make this function as fast as possible, you should explicitely make the snapshot before using it (cf benchmark.au3)
	;
	; Proto C : int WINAPI FFgetPixel(int X, int Y, int NoSnapShot)
	FFGetPixel(x, y, NoSnapShot := "") {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		Result := DllCall(FFDllHandle, "int", "FFGetPixel", "int", x, "int", y, "int", NoSnapShot)
		
		If ( (!isArray(Result)) || (Result[0] = -1) ) {
			Return -1
		}
		Return Result[0]
	}
	
	; FFGetVersion Function - This function returns the version Nb of FastFind DLL
	;
	; Proto C : LPCTSTR WINAPI FFVersion(void)
	FFGetVersion() {
		Result := DllCall(FFDllHandle, "str", "FFVersion")
		If ((!isArray(Result))) {
			
			Return "???"
		}
		Return Result[0]
	}
	
	; FFGetLastError function - This function will return the last error message, if any (won't work if all debug are disabled, as error strings won't be initialized).
	;
	; Proto C : LPCTSTR WINAPI GetLastErrorMsg(void)
	FFGetLastError() {
		Result := DllCall(FFDllHandle, "str", "GetLastErrorMsg")
		If ((!isArray(Result))) {
			
			Return ""
		}
		Return Result[0]
	}
	
	; New in version 1.6 => Save a SnapShot in a .BMP file.
	; Exemple of usage: FFSaveBMP("TOTO")
	FFSaveBMP(FileNameWithNoExtension, ForceNewSnap := false, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local Suffix
		local Result
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			
			Return False
		}
		Result := DllCall(FFDllHandle, "BOOLEAN", "SaveBMP", "int", NoSnapShot, "str", FileNameWithNoExtension)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Suffix := DllCall(FFDllHandle, "int", "GetLastFileSuffix")
		If (isArray(Result)) {
			If (Result[0]>0) {
				LastFileNameParam = FileNameWithNoExtension+".BMP"
			} Else {
				LastFileNameParam = FileNameWithNoExtension+"_"+Result[0]+".BMP"
			}
		}
		return true
	}
	
	; New in version 1.6 => Save a SnapShot in a JPEG file.
	; Exemple of usage: FFSaveJPG("TOTO")
	FFSaveJPG(FileNameWithNoExtension, QualityFactor := 85, ForceNewSnap := false, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		local Suffix
		local Result
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			
			Return False
		}
		Result := DllCall(FFDllHandle, "BOOLEAN", "SaveJPG", "int", NoSnapShot, "str", FileNameWithNoExtension, "ULONG", QualityFactor)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Suffix = DllCall(FFDllHandle, "int", "GetLastFileSuffix")
		If (isArray(Result)) {
			If (Result[0]>0) {
				LastFileNameParam := FileNameWithNoExtension+".JPG"
			} Else {
				LastFileNameParam := FileNameWithNoExtension+"_"+Result[0]+".JPG"
			}
		}
		return true
	}
	
	; Gives the FileName of the last file written with FFSaveJPG of FFSaveBMP
	FFGetLastFileName() {
		return LastFileNameParam
	}
	
	; Change a SnapShot so that it keeps only the pixels that are different from another SnapShot.
	; modified by frank10
	; Exemple :
	;   FFSnapShot(0, 0, 0, 0, 1) ; Takes FullScreen SnapShot N°1
	;   Sleep(1000)				  ; Wait 1 second
	;   FFSnapShot(0, 0, 0, 0, 2) ; Takes another SnapShot (N°2)
	;   FFKeepChanges(1, 2, 8)       ; SnapShot N°1 will have all pixels black, except those that have changed between the 2 SnapShots with a shadevariation of 8. SnapShot N°2 is kept unchanged.
	;   FFSaveBMP("snapshot", false, 0,0,0,0, 1) ; Saves the result into snapshot.bmp
	;
	;Prototype : int WINAPI KeepChanges(int NoSnapShot, int NoSnapShot2, int ShadeVariation);  // ** Changed in version 2.0 : ShadeVariation added **
	FFKeepChanges(NoSnapShot1, NoSnapShot2, ShadeVariation := 0) {
		Result = DllCall(FFDllHandle, "int", "KeepChanges", "int", NoSnapShot1, "int", NoSnapShot2, "int", ShadeVariation)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
	
	; Change a SnapShot so that it keeps only the color (or colors if a list is used) asked. All other pixels will be black.
	; Exemple :
	;   FFSnapShot(0, 0, 0, 0, 1) ; Takes FullScreen SnapShot N°1
	;   Sleep(1000)				  ; Wait 1 second
	;   FFSnapShot(0, 0, 0, 0, 2) ; Takes another SnapShot (N°2)
	;   FFKeepChanges(1, 2)       ; SnapShot N°1 will have all pixels black, except those that have changed between the 2 SnapShots. SnapShot N°2 is kept unchanged.
	;   FFResetColors()           ; Rest of the list of colors
	;   local Couleurs[2]=[0x00FF0000, 0x000000FF] ; Pure blue and pure red
	;   FFAddColor(Couleurs)
	;   FFKeepColor(-1, 60, false, 0,0,0,0, 1, -1) ;  As the SnapShot N°1 now has only very few pixels (only changes), we can now make de detection with very high ShadeVariation value
	;                                              ;  After this step, the SnapShot N°1 will only have blue and red pixels left.
	;Prototype : int WINAPI KeepColor(int NoSnapShot, int ColorToFind, int ShadeVariation);
	FFKeepColor(ColorToFind, ShadeVariation := 0, ForceNewSnap := true, Left := 0, Top := 0, Right := 0, Bottom := 0, NoSnapShot := "", WindowHandle := -1) {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (!this.SnapShotPreProcessor(Left, Top, Right, Bottom, ForceNewSnap, NoSnapShot, WindowHandle)) {
			
			Return False
		}
		Result = DllCall(FFDllHandle, "int", "KeepColor", "int", NoSnapShot, "int", ColorToFind, "int", ShadeVariation)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
	
	; FFDrawSnapShot will draw the SnapShot back on screen (using the same Window and same position).
	; Can also be used on modified SnapShots (after use of FFsetPixel, FFKeepChanges or FFKeepColor)
	; Proto C: bool WINAPI DrawSnapShot(int NoSnapShot);
	FFDrawSnapShot(NoSnapShot := "") {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (FFLastSnapStatus[NoSnapShot] != 1) {
			Return False
		}
		
		Result = DllCall(FFDllHandle, "BOOLEAN", "DrawSnapShot", "int", NoSnapShot)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
	
	; FFSetPixel will change the color of a pixel in a given SnapShot
	;bool WINAPI FFSetPixel(int x, int y, int Color, int NoSnapShot);
	FFSetPixel(x, y, Color, NoSnapShot := "") {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (FFLastSnapStatus[NoSnapShot] != 1) {
			Return False
		}
		Result := DllCall(FFDllHandle, "BOOLEAN", "FFSetPixel", "int", x, "int", y, "int", Color, "int", NoSnapShot)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
	
	;bool WINAPI DuplicateSnapShot(int Src, int Dst);
	FFDuplicateSnapShot(NoSnapShotSrc, NoSnapShotDst) {
		; If NoSnapShotSrc do not exist, then make the capture
		if (!this.SnapShotPreProcessor(0, 0, 0, 0, false, NoSnapShotSrc, -1)) {
			
			Return False
		}
		Result := DllCall(FFDllHandle, "BOOLEAN", "DuplicateSnapShot", "int", NoSnapShotSrc, "int", NoSnapShotDst)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
	
	; GetRawData Function - Gives RawBytes of the SnapShot
	; Wrapper made by frank10
	; If unsuccessful, @Error = 1 and returns 0
	; Success: 	it returns a string stride with the Raw bytes of the SnapShot in 8 Hex digits (BGRA) of pixels from left to right, top to bottom
	;           every pixel can be accessed like this:   StringMid(sStride, pixelNo *8 +1  ,8)  and you get 685E5B00 68blue 5Egreen 5Bred 00alpha
	;Proto C: int * WINAPI GetRawData(int NoSnapShot, int &NbBytes);
	;FFGetRawData(NoSnapShot := "") {
	;	Local t_Raw
	;	Local sStrid
	;	aResult = DllCall(FFDllHandle, "ptr", "GetRawData", "int", NoSnapShot, "int*", 0)
	;	If ( !isArray(aResult) ) {
	;		Return False
	;;	}
	;	t_Raw  := DllStructCreate("ubyte["aResult[2]"]",aResult[0])
	;	sStride := DllStructGetData(t_Raw, 1)
	;	sStride := StringRight(sStride,StringLen(sStride)-2)
	;	Return sStride
	;}
	
	; FFComputeMeanValues Function - Gives mean Red, Green and Blue values, useful for detecting changed areas
	; Wrapper made by frank10
	; If unsuccessful, @Error = 1 and returns 0
	; It returns an array with:
	; [0]: MeanRed
	; [1]: MeanGreen
	; [2]: MeanBlue
	; Proto C : int WINAPI ComputeMeanValues(int NoSnapShot, int &MeanRed, int &MeanGreen, int &MeanBlue);
	FFComputeMeanValues(NoSnapShot := "") {
		local MeanResult
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		aResult := DllCall(FFDllHandle, "int", "ComputeMeanValues", "int", NoSnapShot, "int*", 0, "int*", 0, "int*", 0)
		If ( !isArray(aResult) OR aResult[0] != 1) {
			Return False
		}
		MeanResult[3] := [aResult[2], aResult[3], aResult[4]] ; MeanRed, MeanGreen, MeanBlue
		return MeanResult
	}
	
	; FFApplyFilterOnSnapshot Function - apply an AND filter on each pixels in the SnapShot
	; Wrapper made by frank10
	; If unsuccessful, @Error = 1 and returns 0
	; Success: It returns 1
	;Proto C : int WINAPI ApplyFilterOnSnapShot(int NoSnapShot, int Red, int Green, int Blue); // ** New in version 2.0 **
	FFApplyFilterOnSnapShot(Red, Green, Blue, NoSnapShot := "") {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		aResult = DllCall(FFDllHandle, "int", "ApplyFilterOnSnapShot", "int", NoSnapShot, "int", Red, "int", Green, "int", Blue)
		If ( !isArray(aResult) OR aResult[0] != 1) {
			Return False
		}
		return true
	}
	
	; FFDrawSnapShotXY Function - same as DrawSnapShot, with specific top-left position for drawing
	; Wrapper made by frank10
	; If unsuccessful, @Error = 1 and returns 0
	; Success: returns 1
	;Proto C : bool WINAPI DrawSnapShotXY(int NoSnapShot, int X, int Y); // ** New in version 2.0 **
	FFDrawSnapShotXY(iX, iY, NoSnapShot := "") {
		if (!NoSnapShot) {
			NoSnapShot := FFLastSnap
		}
		if (FFLastSnapStatus[NoSnapShot] != 1) {
			
			Return False
		}
		Result:== DllCall(FFDllHandle, "BOOLEAN", "DrawSnapShotXY", "int", NoSnapShot, "int", iX, "int", iY)
		If ((!isArray(Result)) || Result[0] != 1) {
			Return False
		}
		Return true
	}
}

isArray(arrOrObj) { ; https://www.autohotkey.com/boards/viewtopic.php?f=76&t=64332
	return !ObjCount(arrOrObj) || ObjMinIndex(arrOrObj) == 1 && ObjMaxIndex(arrOrObj) == ObjCount(arrOrObj) && arrOrObj.Clone().Delete(1, arrOrObj.MaxIndex()) == ObjCount(arrOrObj)
}
