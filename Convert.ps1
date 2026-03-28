param(
	[parameter(Mandatory, HelpMessage="Options: default, _full_1080p_AV1, _1080p_AV1, _38_1080p_AV1, _720p_AV1, _42_720p_AV1")]
	[string]$preset,
	[parameter(Mandatory, HelpMessage="Options: Y, N")]
	[string]$skipAV1,
	[parameter(Mandatory=$false, HelpMessage="Options: 6,5,4,3,2")]
	[string]$limit,
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
     "[$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))]"
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

###################################################
if ($preset -eq $null -or $preset -eq "default" -or $preset.length -lt 3) {
	$preset = "_1080p_AV1"
	Write-Host "Using default preset: `"_1080p_AV1`"" -foreground yellow
	Write-Output "$(Get-TimeStamp) Using default preset: `"_1080p_AV1`"" >> $PSScriptRoot +"\log_1080p_AV1.log"
}

switch ($preset) {
    { $_ -in "default", "_full_1080p_AV1", "_1080p_AV1", "_38_1080p_AV1", "_720p_AV1", "_42_720p_AV1" } {
        Write-Host "Valid preset: $PRESET"
        # Logic for valid presets here
    }
    Default {
        Write-Error "Error: Invalid PRESET"
        Write-Error "Error: PRESET must be one of: default, _full_1080p_AV1, _1080p_AV1, _38_1080p_AV1, _720p_AV1, _42_720p_AV1"
        exit 2
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

$presetFile = $PSScriptRoot + "\presets.json"
$logfile = $PSScriptRoot +"\log"+$preset+".log"
$errorfile = $PSScriptRoot +"\error"+$preset+".log"
$loop = 0
$success = 0
$skipped = 0
$failed = 0
$options = ""

if ($limit -eq $null) {
	$options = ""
}  elseif ($limit -eq "6") {
	$options = "-x lp=6"
}  elseif ($limit -eq "5") {
	$options = "-x lp=5"
}  elseif ($limit -eq "4") {
	$options = "-x lp=4"
} elseif ($limit -eq "3") {
	$options = "-x lp=3"
} elseif ($limit -eq "2") {
	$options = "-x lp=2"
} else {
	$options = "-x lp=4"
}


Write-Output "`n$(Get-TimeStamp) *******************************************************************************" >> $logfile
Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
Write-Output "$(Get-TimeStamp) Starting New Video File Conversion Run" >> $logfile
Write-Output "$(Get-TimeStamp) Process Directory: $dir" >> $logfile
Write-Output "$(Get-TimeStamp) Preset: $preset" >> $logfile
Write-Output "$(Get-TimeStamp) Options: $options" >> $logfile
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
			$loop++

			Write-Host "`*******************************************************************************"
			Write-Host "Processing Loop $loop :  $fileName" -foreground green
			Write-Host "*******************************************************************************"
			Write-Host "Input File:  $file" -foreground green
			Write-Host "Output File: $outFile" -foreground green
			
			# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			if (Test-Path $outFile){
				Write-Host "Output file already exist!!!" -ForegroundColor Red
				Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				Write-Output "$(Get-TimeStamp) Output file already exist!!!" >> $logfile
				Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				$skipped++
				continue
			}

			if (($skipAV1 -eq "Y") -and ("$fileName" -eq "$av1Name")){
				Write-Host "Input file is already AV1 and SKIP option was chosen!!!" -ForegroundColor Red
				#Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				#Write-Output "$(Get-TimeStamp) Input file is already AV1 and SKIP option was chosen!!!" >> $logfile
				#Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				$skipped++
				continue
			}

			if ("$fileName" -eq "$dupName"){
				Write-Host "Input file is same as destination file!!!" -ForegroundColor Red
				Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				Write-Output "$(Get-TimeStamp) Input file is same as destination file!!!" >> $logfile
				Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
				$skipped++
				continue
			}

			Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile
			Write-Output "$(Get-TimeStamp) Processing Loop $loop :  $fileName" >> $logfile
			Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $logfile
			Write-Output "$(Get-TimeStamp) Input File:  $file" >> $logfile
			Write-Output "$(Get-TimeStamp) Output File: $outFile" >> $logfile


			#Invoking Handbrake for file transcoding
			$incomplete = $true
			[string] $handbrake = $handbrakeclishortpath + " -i `"$file`" -o `"$outFile`" --preset-import-file `"$presetFile`" -Z `"$preset`" $options"
			#Write-Host "Invoking $handbrake"
			Invoke-Expression $handbrake
			# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			
			#Compare file sizes
			$fileSize = (Get-Item $file).Length / 1MB
			$outFileSize = (Get-Item $outFile).Length / 1MB
			Write-Host "$fileSize -> $file" -foreground green
			Write-Host "$outFileSize -> $outFile" -foreground green
			Write-Output "$(Get-TimeStamp) Input Size  $fileSize"  >> $logfile
			Write-Output "$(Get-TimeStamp) Output Size $outFileSize"  >> $logfile

			if ($outFileSize -lt $fileSize) {
				$success++
				# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				Write-Host "Successful conversion" -foreground green
				Write-Host "$file" -foreground green
				Write-Output "$(Get-TimeStamp) +++ SUCCESS" >> $logfile
				if ($outFileSize -gt $fileSize/4) {
					Remove-Item $file
				}else{
					Write-Output "$(Get-TimeStamp) WARNING: less than 20% of original" >> $logfile
					Write-Output "$(Get-TimeStamp) WARNING: -> $outFile" >> $logfile
					Write-Output "$(Get-TimeStamp) WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $logfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Write-Output "$(Get-TimeStamp) Processing Loop $loop :  $fileName" >> $errorfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: less than 20% of original" >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> input  $fileSize -> $file"  >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> output $outFileSize -> $outFile"  >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> $outFile" >> $errorfile
					Write-Output "$(Get-TimeStamp) WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $errorfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Move-Item -Path $file -Destination $PSScriptRoot\$fileName
				}
			}else{
				# $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
				$failed++
				Write-Host "Conversion Failed" -foreground red
				Write-Host "$file" -foreground red
					Write-Output "$(Get-TimeStamp) ERROR: filesize greater than original or incomplete" >> $logfile
					Write-Output "$(Get-TimeStamp) ERROR: -> $outFile" >> $logfile
					Write-Output "$(Get-TimeStamp) ERROR: -> Moving converted file to: $PSScriptRoot\$fileName"  >> $logfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Write-Output "$(Get-TimeStamp) Processing Loop $loop :  $fileName" >> $errorfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: filesize greater than original or incomplete" >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> input  $fileSize -> $file"  >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> output $outFileSize -> $outFile"  >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> $outFile" >> $errorfile
					Write-Output "$(Get-TimeStamp) ERROR: -> Moving converted file to: $PSScriptRoot\$outFileName"  >> $errorfile
					Write-Output "$(Get-TimeStamp) *******************************************************************************"  >> $errorfile
					Move-Item -Path $outFile -Destination $PSScriptRoot\$outFileName
			}
			
			#Clear outfile so cleanup doesn't delete the last file
			$incomplete = $false

			New-BalloonTip -BalloonTipIcon info -BalloontipText "$justname.mp4 finished" -BalloonTipTitle "Encoding completed"
		}
	}
	finally {
		#The Cleanup "Trap"
		# This block runs NO MATTER WHAT (Ctrl+C, Error, or Completion)
		if ($incomplete -and (Test-Path $outFile)) {
			Write-Warning "Cleaning up partial file: $outFile"
			Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile
			Write-Output "$(Get-TimeStamp) ERROR: Incomplete" >> $errorfile
			Write-Output "$(Get-TimeStamp) ERROR: Cleaning up partial file: $outFile" >> $errorfile
			Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile
			Remove-Item $outFile -Force
			$failed++
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

Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile
Write-Output "$(Get-TimeStamp) Total Files: $loop" >> $logfile
Write-Output "$(Get-TimeStamp) Success: $success" >> $logfile
Write-Output "$(Get-TimeStamp) Skipped: $skipped" >> $logfile
Write-Output "$(Get-TimeStamp) Failed: $failed" >> $logfile

Write-Output "$(Get-TimeStamp) *******************************************************************************" >> $logfile


popd

# clear the variables!
Remove-ScriptVariables($MyInvocation.MyCommand.Name)
