# Small helper for driving the Dramix window during verification.
#   . .\tools\win_ui.ps1
#   Shot "out.png"; Click 150 145
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinUi {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, int e);
  public const uint LDOWN = 0x0002, LUP = 0x0004;
  public static void Click(int x, int y) {
    SetCursorPos(x, y);
    System.Threading.Thread.Sleep(150);
    mouse_event(LDOWN, 0, 0, 0, 0);
    System.Threading.Thread.Sleep(70);
    mouse_event(LUP, 0, 0, 0, 0);
  }
}
"@

function Get-DramixWindow {
  $p = Get-Process dramix -ErrorAction SilentlyContinue
  if (-not $p) { throw "dramix is not running" }
  return $p
}

function Focus-App {
  $p = Get-DramixWindow
  [void][WinUi]::ShowWindow($p.MainWindowHandle, 3)   # maximise
  [void][WinUi]::SetForegroundWindow($p.MainWindowHandle)
  Start-Sleep -Milliseconds 700
}

function Shot([string]$Path) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $g.Dispose()
  $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
  Write-Host "shot -> $Path ($([math]::Round((Get-Item $Path).Length/1KB)) KB)"
}

function Click([int]$X, [int]$Y, [int]$WaitMs = 2500) {
  [WinUi]::Click($X, $Y)
  Start-Sleep -Milliseconds $WaitMs
  Write-Host "clicked $X,$Y"
}
