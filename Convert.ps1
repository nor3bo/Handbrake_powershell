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
$files = (Get-ChildItem "$dir\*" -include *.avi,*.mkv,*.ogm,*.wmv, *.mp4 -Recurse)
$runningDir = $PSScriptRoot
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

if ($preset -eq $null -or $preset -eq "default" -or $preset.length -lt 3) {
	$preset = "_1080p_AV1"
	Write-Host "Using default preset: `"_1080p_AV1`"" -foreground yellow
	Write-Output "$timestamp Using default preset: `"_1080p_AV1`"" >> $PSScriptRoot +"\log_1080p_AV1.txt"
}

$presetFile = $PSScriptRoot + "\presets.json"
$logfile = $PSScriptRoot +"\log"+$preset+".txt"
$errorfile = $PSScriptRoot +"\error"+$preset+".txt"


Write-Output "`n$timestamp*******************************************************************************" >> $logfile
Write-Output "$timestamp Starting New Video File Conversion Run" >> $logfile
Write-Output "$timestamp Process Directory: $dir" >> $logfile
Write-Output "$timestamp*******************************************************************************"  >> $logfile

if ($files.length -ge 1){
	ForEach ($file in $files){
		[string] $fileName = $file.name
		[string] $justName = $file.name.substring(0,$file.name.length-4)
		[string] $dupName = $file.name.substring(0,$file.name.length-($preset.length+4)) + $preset + ".mp4"
		[string] $outFile = $file.FullName.substring(0,$file.FullName.length-4) + $preset + ".mp4"
		[string] $outFileName = $justName + $preset + ".mp4"
		
		[string] $av1Name = $file.name.substring(0,$file.name.length-7) + "AV1.mp4"

		
		Write-Host "`n*******************************************************************************"
		Write-Host "Processing:  $file" -foreground green
		Write-Host "*******************************************************************************"

		$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		Write-Output "`n$timestamp *******************************************************************************" >> $logfile
		Write-Output "$timestamp Processing:  $file" >> $logfile
		Write-Output "$timestamp*******************************************************************************"  >> $logfile

		if (Test-Path $outFile){
			Write-Host "Output file already exist!!!" -ForegroundColor Red
			Write-Output "$timestamp Output file already exist!!!" >> $logfile
			continue
		}

		if (($skipAV1 -eq "Y") -and ("$fileName" -eq "$av1Name")){
			Write-Host "Input file is already AV1 and SKIP option was chosen!!!" -ForegroundColor Red
			Write-Output "$timestamp Input file is already AV1 and SKIP option was chosen!!!" >> $logfile
			continue
		}

		if ("$fileName" -eq "$dupName"){
			Write-Host "Input file is same as destination file!!!" -ForegroundColor Red
			Write-Output "$timestamp Input file is same as destination file!!!" >> $logfile
			continue
		}

		Write-Host "Output File: $outFile" -foreground green
		Write-Output "$timestamp Output File: $outFile" >> $logfile


		#Invoking Handbrake for file transcoding
		[string] $handbrake = $handbrakeclishortpath + " -i `"$file`" -o `"$outFile`" --preset-import-file `"$presetFile`" -Z `"$preset`""
		
		Invoke-Expression $handbrake
		$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
		
		#Compare file sizes
		$fileSize = (Get-Item $file).Length / 1MB
		$outFileSize = (Get-Item $outFile).Length / 1MB
		Write-Host "$fileSize -> $file" -foreground green
		Write-Host "$outFileSize -> $outFile" -foreground green
		Write-Output "$timestamp input  $fileSize -> $file"  >> $logfile
		Write-Output "$timestamp output $outFileSize -> $outFile"  >> $logfile

		if ($outFileSize -lt $fileSize) {
			$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			Write-Host "Successful conversion" -foreground green
			Write-Host "$file" -foreground green
			Write-Output "$timestamp SUCCESS +++" >> $logfile
			Write-Output "$timestamp -> $outFile" >> $logfile
			if ($outFileSize -gt $fileSize/4) {
				Remove-Item $file
			}else{
				Write-Output "$timestamp WARNING: less than 20% of original" >> $logfile
				Write-Output "$timestamp WARNING: -> $outFile" >> $logfile
				Write-Output "$timestamp WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $logfile
				Write-Output "$timestamp WARNING: less than 20% of original" >> $errorfile
				Write-Output "$timestamp WARNING: -> input  $fileSize -> $file"  >> $errorfile
				Write-Output "$timestamp WARNING: -> output $outFileSize -> $outFile"  >> $errorfile
				Write-Output "$timestamp WARNING: -> $outFile" >> $errorfile
				Write-Output "$timestamp WARNING: -> Moving original to: $PSScriptRoot\$fileName"  >> $errorfile
				Move-Item -Path $file -Destination $PSScriptRoot\$fileName
			}
		}else{
			$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
			Write-Host "Conversion Failed" -foreground red
			Write-Host "$file" -foreground red
				Write-Output "$timestamp ERROR: filesize greater than original or incomplete" >> $logfile
				Write-Output "$timestamp ERROR: -> $outFile" >> $logfile
				Write-Output "$timestamp ERROR: -> Moving converted file to: $PSScriptRoot\$fileName"  >> $logfile
				Write-Output "$timestamp ERROR: filesize greater than original or incomplete" >> $errorfile
				Write-Output "$timestamp ERROR: -> input  $fileSize -> $file"  >> $errorfile
				Write-Output "$timestamp ERROR: -> output $outFileSize -> $outFile"  >> $errorfile
				Write-Output "$timestamp ERROR: -> $outFile" >> $errorfile
				Write-Output "$timestamp ERROR: -> Moving converted file to: $PSScriptRoot\$outFileName"  >> $errorfile
				Move-Item -Path $outFile -Destination $PSScriptRoot\$outFileName
		}
		
		Write-Output "$timestamp *******************************************************************************" >> $logfile

		New-BalloonTip -BalloonTipIcon info -BalloontipText "$justname.mp4 finished" -BalloonTipTitle "Encoding completed"
	}
}else{
	# no files found to process
	# either none existed, or there were matching MP4 files for them
    Write-Host "`n*******************************************************************************"
    Write-Host "No files to process" -foreground yellow
    Write-Host "*******************************************************************************"

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Output "`n$timestamp*******************************************************************************" >> $logfile
    Write-Output "$timestamp No files to process" >> $logfile
    Write-Output "$timestamp*******************************************************************************" >> $logfile
}

New-BalloonTip -BalloonTipIcon info -BalloontipText "All files completed!" -BalloonTipTitle "Encoding completed"
# Speak -phrase "Encoding finished."
popd

# clear the variables!
Remove-ScriptVariables($MyInvocation.MyCommand.Name)
