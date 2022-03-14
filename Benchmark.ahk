#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.
#Include, FastFind.ahk

;ProgressOn ( "FastFind Benchmark", "Running...", "Native PixelGetcolor")
Progress, b w200, Native PixelGetcolor, Running..., FastFind Benchmark
begin := TimerInit()
global color :=""
Loop, 100 {
	PixelGetcolor, testCOlor , A_Index, 500
}
dif := TimerDiff(begin)

Progress,10, Native PixelSearch
; Use Native PixelSearch() on FullScreen (1920x1080) x 100 with ShadeVariation
begin1 := TimerInit()
Loop, 100 {
	PixelSearch, Px, Py, 200, 200, 300, 300, 0x9d6346, 3, Fast
	}
dif1 := TimerDiff(begin1)

Progress,20, FFGetPixel
; Processing time comparaison with FastFind equivalent : FFGetPixel, that works on a SnapShot.
FF.FFSnapShot() ; To keep it simple, a FullScreen capture here
begin2 := TimerInit()
Loop, 2000 {
  ; Func FFGetPixel(x, y, NoSnapShot=FFLastSnap)
  newColor := FF.FFGetPixel(%A_Index%, 500)
}
dif2 := TimerDiff(begin2)
;MsgBox %newColor%

Progress,30, GetPixel direct DllCall
; Same with direct dll call => nearly 40% faster
FF.FFSnapShot() ; To keep it simple, a FullScreen capture here
begin22 := TimerInit()
Loop, 3000 {
	DllCall("FastFind64\FFGetPixel", "int", %A_Index%, "int", 500, "int", FFLastSnap)
}
dif22 := TimerDiff(begin22)

Progress, 40, 10x10 FFSnapShot
; SnapShot BenchMark : 100 SnapShots of 10x10 areas
begin3 := TimerInit()
Loop, 100 {
  ;Func FFSnapShot(const Left=0, const Top=0, const Right=0, const Bottom=0, const NoSnapShot=FFDefaultSnapShot, const WindowHandle=-1)
	FF.FFSnapShot(0,0,9,9) ; 10x10 pixels area
}
dif3 := TimerDiff(begin3)

Progress,50, FullScreen FFSnapShot
; SnapShot BenchMark : 100 FullScreen SnapShots
begin4 := TimerInit()
Loop, 100 {
  ;Func FFSnapShot(const Left=0, const Top=0, const Right=0, const Bottom=0, const NoSnapShot=FFDefaultSnapShot, const WindowHandle=-1)
	FF.FFSnapShot() ; FullScreen Capture
}
dif4 := TimerDiff(begin4)

Progress,60, Simple FFNearestPixel
; FFNearestPixel BenchMark : 500 simple pixel search in 200x200 area
a := FF.FFSnapShot(0,0,199,199) ; 200x200 pixels
begin5 := TimerInit()
Loop, 500 {
  ; Func FFNearestPixel(PosX, PosY, Color, ForceNewSnap=true, Left=0, Top=0, Right=0, Bottom=0, NoSnapShot=FFLastSnap, WindowHandle=-1)
	FF.FFNearestPixel(%A_Index%,%A_Index%,0x002545FA,false) ; Pixel search in 200x200 area, don't force SnapShots each time
}
dif5 := TimerDiff(begin5)

Progress,70, FFNearestSpot - simple usage
; FFNearestPixel BenchMark : 200 pixel search in FullScreen and ShadeVariation
; As NearestPixel do not expose ShadeVariation, we use FFNearestSpot(SizeSearch, NbPixel, PosX, PosY, Color, ShadeVariation=0, ForceNewSnap=true, Left=0, Top=0, Right=0, Bottom=0, NoSnapShot=FFLastSnap, WindowHandle=-1)
a := FF.FFSnapShot() ; FullScreen
begin52 := TimerInit()
Loop, 200 {
  ; Func FFNearestSpot(SizeSearch, NbPixel, PosX, PosY, Color, ShadeVariation=0, ForceNewSnap=true, Left=0, Top=0, Right=0, Bottom=0, NoSnapShot=FFLastSnap, WindowHandle=-1)
	FF.FFNearestSpot(1, 1, %A_Index%,%A_Index%, 0x00FF5511, 2, false)
}
dif52 := TimerDiff(begin52)


Progress,80, FFNearestSpot - complex usage
; FFNearestPixel BenchMark : 500 simple pixel search in 200x200 area
; SnapShot BenchMark : 100 FullScreen SnapShots
a := FF.FFSnapShot() ; FullScreen Capture
FF.FFAddColor(0x453456)
FF.FFAddColor(0xFF0034)
FF.FFAddColor(0x76FF98)
FF.FFAddColor(0x8723FF)
FF.FFAddColor(0x771122)
FF.FFAddExcludedArea(5,10,10,15)
FF.FFAddExcludedArea(52,52,80,80)
FF.FFAddExcludedArea(120,130,100,180)
begin6 := TimerInit()
Loop, 100 {
  ; Func FFNearestSpot(SizeSearch, NbPixel, PosX, PosY, Color, ShadeVariation=0, ForceNewSnap=true, Left=0, Top=0, Right=0, Bottom=0, NoSnapShot=FFLastSnap, WindowHandle=-1)
	FF.FFNearestSpot(20, 50, 100, 100, -1, 10, false) ; With ShadeVariation, don't force SnapShots each time
}
dif6 := TimerDiff(begin6)

Progress,90, FFBestSpot  - complexe usage
begin7 := TimerInit()
Loop, 100 {
  ; Func FFBestSpot(SizeSearch, MinNbPixel, OptNbPixel, PosX, PosY, Color, ShadeVariation=0, ForceNewSnap=true, Left=0, Top=0, Right=0, Bottom=0, NoSnapShot=FFLastSnap, WindowHandle=-1)	
	FF.FFBestSpot(20, 2, 50, 100, 100, -1, 10, false) ; Same as before, but can accept down to 2 pixels only instead of 50
}
dif7 := TimerDiff(begin7)


Progress, Off
var1 := TimeSpan(dif,100)
var2 := TimeSpan(dif1,100)
var3 := TimeSpan(dif2,2000)
var4 := TimeSpan(dif22,3000)
var5 := TimeSpan(dif3,100)
var6 := TimeSpan(dif4,100)
var7 := TimeSpan(dif5,500)
var8 := TimeSpan(dif52,200)
var9 := TimeSpan(dif6,100)
var10 := TimeSpan(dif7,100)
MsgBox Elpased time for :`n`nPixelGetColor%var1%`nFullScreen PixelSearch with ShadeVariation%var2%`n`nFFGetPixel%var3%`nSame with direct dllCall%var4%`n`nSnapShot 10x10 area %var5%`nFullSreen SnapShot%var6%`nSimple Pixel Searches in 200x200 area%var7%`nPixel Searches with ShadeVariation in FullScreen%var8%`nComplexe FullScreen searches (20x20 Spot, List of 5 colors with ShadeVariation and 3 excluded rectangles)%var9%`nSame as before, but searches best spot containing from 2 to 50 good pixels (FFBestSpot)%var10%
;MsgBox Elpased time for :`n`nPixelGetColor TimeSpan(%dif%,100)
TimerInit() {
	return A_TickCount
}

TimerDiff(StartTime) {
	return A_TickCount - StartTime
}

TimeSpan(dif, Nb) {
	res := (dif / 1000)/Nb
	if (res >= 0.010) { 
		return " = "Round(res*1000)" mS (" Nb " runs):"
	} Else {
		return " = "Round(res*1000000)" nS (" Nb " runs)"
	}
}
