param(
	[parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$true)] 
	$searchtag,
	[parameter(ValueFromPipeline=$true, ValueFromPipelineByPropertyName=$true, Mandatory=$false)] 
	$replacetag = "",
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
$files = (Get-ChildItem "$dir\*" -include *.avi,*.mkv,*.ogm,*.wmv, *.mp4, *.srt -Recurse)
$runningDir = $PSScriptRoot
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$escapedTag = [regex]::Escape($searchtag)

$logfile = $PSScriptRoot +"\file-rename.log"
$errorfile = $PSScriptRoot +"\rename-error.log"


Write-Output "$timestamp dir: $dir" >> $logfile
Write-Output "$timestamp searchtag: $searchtag" >> $logfile
Write-Output "$timestamp escapedTag: $escapedTag" >> $logfile
Write-Output "$timestamp replacetag: $replacetag" >> $logfile

$matchingFiles = $files | Where-Object { $_.Name -like "*$searchtag*" }
$matchingFiles = $files | Where-Object { $_.Name.Contains($searchtag) -or $_.Name -like "*$searchtag*" }

if ($null -eq $matchingFiles) {
    Write-Host "No files found matching the tag." -ForegroundColor Yellow
	popd
    return
}
if ($matchingFiles.count -ge 1){
	
	Write-Host "Found $($matchingFiles.Count) matching file(s)." -ForegroundColor Green
	
	ForEach ($file in $matchingFiles){
		
		$newName = ($file.Name -replace $escapedTag, $replacetag).Replace("..", ".").Replace("  ", " ").Trim()
		$newName = $newName -replace " \.", "."

		Write-Host "Processing: $($file.Name)" -ForegroundColor Gray
		Write-Host "   Result: " -NoNewline
		Write-Host "$($file.Name)" -ForegroundColor Red -NoNewline
		Write-Host " -> " -NoNewline
		Write-Host "$newName" -ForegroundColor Green
		
		# Execute the rename
		Rename-Item -LiteralPath $file.FullName -NewName $newName

		Write-Output "$timestamp in:  $file" >> $logfile
		Write-Output "$timestamp out: $newName" >> $logfile
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
