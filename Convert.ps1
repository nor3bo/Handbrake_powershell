param(
	[parameter(Mandatory, HelpMessage="Options: default, _1080p_AV1, _38_1080p_AV1, _720p_AV1, _42_720p_AV1")]
	[string]$preset,
	[parameter(Mandatory, HelpMessage="Options: Y, N")]
	[string]$skipAV1,
	[parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$false)] 
	$dir,
	[int] $percentComplete = 0,
	[int] $filesCompleted = 0
)

function New-BalloonTip{ # http://powershell.com/cs/blogs/tips/archive/2011/09/27/displaying-balloon-tip.aspx
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
    [parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$false, HelpMessage="No icon specified. Options are None, Info, Warning, and Error!")] 
    $BalloonTipIcon,
    [parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$false, HelpMessage="No text specified!")] 
    $BalloonTipText,
    [parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$true, HelpMessage="No title specified!")] 
    $BalloonTipTitle
	)
  [system.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
  $balloon = New-Object System.Windows.Forms.NotifyIcon
  $path = Get-Process -id $pid | Select-Object -ExpandProperty Path
  $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($path)
  $balloon.Icon = $icon
  $balloon.BalloonTipIcon = $BalloonTipIcon
  $balloon.BalloonTipText = $BalloonTipText
  $balloon.BalloonTipTitle = $BalloonTipTitle
  $balloon.Visible = $true
  $balloon.ShowBalloonTip(10000)
    
  # Icon options are None, Info, Warning, Error
} # end function New-BalloonTip

function Remove-ScriptVariables($path) {  
	$result = Get-Content $path |  
	ForEach { if ( $_ -match '(\$.*?)\s*=') {      
			$matches[1]  | ? { $_ -notlike '*.*' -and $_ -notmatch 'result' -and $_ -notmatch 'env:'}  
		}  
	}  
	ForEach ($v in ($result | Sort-Object | Get-Unique)){		
		Remove-Variable ($v.replace("$","")) -ErrorAction SilentlyContinue
	}
} # end function Get-ScriptVariables

function Speak	{
	[CmdletBinding(SupportsShouldProcess=$true)]
	param(
		[parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$true)] 
		[string]$phrase
	)
	$voice = New-Object -com SAPI.SpVoice
	$voice.speak($phrase) | Out-Null
} # end function Speak

function Get-TimeStamp {
    # Returns a sortable timestamp string
    return (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}


####################################################
# Determine if Handbrake is installed and where it is
$handbrakeclipath = (Get-ItemProperty -path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Handbrake.exe" -erroraction silentlycontinue).'(Default)' -replace '.exe','cli.exe'
if ($handbrakeclipath -eq $null){
    Write-Host "Handbrake not found on this system. Please install Handbrake and try again." -foregroundcolor red;
    # Speak -phrase "Handbrake not found on this system. Please install Handbrake and try again."
    $ie = new-object -comobject "InternetExplorer.Application"
    $ie.visible = $true
    $ie.navigate("http://www.handbrake.fr")
    exit
}
# get the shortpath to the cli file so we can assemble the line to execute. This will be removed once I work out a couple more issues
$a = New-Object -ComObject Scripting.FileSystemObject
$handbrakeclishortpath = $a.GetFile($handbrakeclipath).ShortPath

####################################################
if ($dir -eq $null){
	# if there is no directory specified 
	$Shell = new-object -com Shell.Application
	$objFolder=$Shell.BrowseForFolder(0, "Choose a folder that contains the files to be converted", 0, 17)
	if ($objFolder -ne $null) {  
		[string] $dir = $objFolder.self.Path
	}
}

pushd

Set-Location $dir

####################################################
# Main 
####################################################
$files = (Get-ChildItem "$dir\*" -include *.avi,*.mkv,*.ogm,*.wmv, *.mp4 -Recurse | Sort-Object Name)
$runningDir = $PSScriptRoot
# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if ($preset -eq $null -or $preset -eq "default" -or $preset.length -lt 3) {
	$preset = "_1080p_AV1"
	Write-Host "Using default preset: `"_1080p_AV1`"" -foreground yellow
	Write-Output "$(Get-TimeStamp) Using default preset: `"_1080p_AV1`"" >> $PSScriptRoot +"\log_1080p_AV1.txt"
}

$presetFile = $PSScriptRoot + "\presets.json"
$logfile = $PSScriptRoot +"\log"+$preset+".txt"
$errorfile = $PSScriptRoot +"\error"+$preset+".txt"


Write-Output "`n$(Get-TimeStamp) *******************************************************************************" >> $logfile
Write-Output "$(Get-TimeStamp) Starting New Video File Conversion Run" >> $logfile
Write-Output "$(Get-TimeStamp) Process Directory: $dir" >> $logfile
Write-Output "$(Get-TimeStamp) Preset: $preset" >> $logfile
Write-Output "$(Get-TimeStamp) Use STOP TRIGGER to end run: `"stop.y`" " >> $logfile
Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile

if ($files.length -ge 1){
	
	try{
		ForEach ($file in $files){
			
			#Manual stop check (like your stop.y)
			if (Test-Path "$runningDir/stop.y") {
				Write-Host "Stop trigger detected." -foreground yellow
			    Write-Output "$(Get-TimeStamp) WARNING: Stop trigger detected." >> $logfile

				Rename-Item -Path "$runningDir/stop.y"  -NewName "$runningDir/stop.n" -Force
				break
			}
			
			[string] $fileName = $file.name
			[string] $justName = $file.name.substring(0,$file.name.length-4)
			[string] $dupName = $file.name.substring(0,$file.name.length-($preset.length+4)) + $preset + ".mp4"
			[string] $outFile = $file.FullName.substring(0,$file.FullName.length-4) + $preset + ".mp4"
			[string] $outFileName = $justName + $preset + ".mp4"
			
			[string] $av1Name = $file.name.substring(0,$file.name.length-7) + "AV1.mp4"

			
			Write-Host "`n*******************************************************************************"
			Write-Host "Processing:  $file" -foreground green
			Write-Host "*******************************************************************************"

			# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			Write-Output "`n$(Get-TimeStamp) *******************************************************************************" >> $logfile
			Write-Output "$(Get-TimeStamp) Processing:  $file" >> $logfile
			Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile

			if (Test-Path $outFile){
				Write-Host "Output file already exist!!!" -ForegroundColor Red
				Write-Output "$(Get-TimeStamp) Output file already exist!!!" >> $logfile
				continue
			}

			if (($skipAV1 -eq "Y") -and ("$fileName" -eq "$av1Name")){
				Write-Host "Input file is already AV1 and SKIP option was chosen!!!" -ForegroundColor Red
				Write-Output "$(Get-TimeStamp) Input file is already AV1 and SKIP option was chosen!!!" >> $logfile
				continue
			}

			if ("$fileName" -eq "$dupName"){
				Write-Host "Input file is same as destination file!!!" -ForegroundColor Red
				Write-Output "$(Get-TimeStamp) Input file is same as destination file!!!" >> $logfile
				continue
			}

			Write-Host "Output File: $outFile" -foreground green
			Write-Output "$(Get-TimeStamp) Output File: $outFile" >> $logfile


			#Invoking Handbrake for file transcoding
			[string] $handbrake = $handbrakeclishortpath + " -i `"$file`" -o `"$outFile`" --preset-import-file `"$presetFile`" -Z `"$preset`""
			Invoke-Expression $handbrake
			# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			
			#Compare file sizes
			$fileSize = (Get-Item $file).Length / 1MB
			$outFileSize = (Get-Item $outFile).Length / 1MB
			Write-Host "$fileSize -> $file" -foreground green
			Write-Host "$outFileSize -> $outFile" -foreground green
			Write-Output "$(Get-TimeStamp) input  $fileSize -> $file"  >> $logfile
			Write-Output "$(Get-TimeStamp) output $outFileSize -> $outFile"  >> $logfile

			if ($outFileSize -lt $fileSize) {
				# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				Write-Host "Successful conversion" -foreground green
				Write-Host "$file" -foreground green
				Write-Output "$(Get-TimeStamp) SUCCESS +++" >> $logfile
				Write-Output "$(Get-TimeStamp) -> $outFile" >> $logfile
				if ($outFileSize -gt $fileSize/4) {
					Remove-Item $file
				}else{
					Write-Output "$(Get-TimeStamp) WARNING: less than 20% of original" >> $logfile
					Write-Output "$(Get-TimeStamp) WARNING: -> $outFile" >> $logfile
					Write-Output "$(Get-TimeStamp) WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $logfile
					Write-Output "$(Get-TimeStamp) WARNING: less than 20% of original" >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> input  $fileSize -> $file"  >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> output $outFileSize -> $outFile"  >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> $outFile" >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $errorfile
					Move-Item -Path $file -Destination $PSScriptRoot\$fileName
				}
			}else{
				# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				Write-Host "Conversion Failed" -foreground red
				Write-Host "$file" -foreground red
					Write-Output "$(Get-TimeStamp) ERROR: filesize greater than original or incomplete" >> $logfile
					Write-Output "$(Get-TimeStamp) ERROR: -> $outFile" >> $logfile
					Write-Output "$(Get-TimeStamp) ERROR: -> Moving converted file to: $PSScriptRoot\$fileName"  >> $logfile
					Write-Output "$(Get-TimeStamp) ERROR: filesize greater than original or incomplete" >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> input  $fileSize -> $file"  >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> output $outFileSize -> $outFile"  >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> $outFile" >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> Moving converted file to: $PSScriptRoot\$outFileName"  >> $errorfile
					Move-Item -Path $outFile -Destination $PSScriptRoot\$outFileName
			}
			
			#Clear outfile so cleanup doesn't delete the last file
			$outFile = $null
			Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile

			New-BalloonTip -BalloonTipIcon info -BalloontipText "$justname.mp4 finished" -BalloonTipTitle "Encoding completed"
		}
	}
	finally {
		#The Cleanup "Trap"
		# This block runs NO MATTER WHAT (Ctrl+C, Error, or Completion)
		if ($null -ne $outFile -and (Test-Path $outFile)) {
			Write-Warning "Cleaning up partial file: $outFile"
			Remove-Item $outFile -Force
			popd
		}
	}
}else{
	# no files found to process
	# either none existed, or there were matching MP4 files for them
    Write-Host "`n*******************************************************************************"
    Write-Host "No files to process" -foreground yellow
    Write-Host "*******************************************************************************"

    # $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "`n$(Get-TimeStamp) *******************************************************************************" >> $logfile
    Write-Output "$(Get-TimeStamp) No files to process" >> $logfile
    Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile
}

New-BalloonTip -BalloonTipIcon info -BalloontipText "All files completed!" -BalloonTipTitle "Encoding completed"
# Speak -phrase "Encoding finished."
popd

# clear the variables!
Remove-ScriptVariables($MyInvocation.MyCommand.Name)
