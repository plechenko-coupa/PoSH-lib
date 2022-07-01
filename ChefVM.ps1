$ChefDir = "$HOME\.chef"
$ChefVMDir = "$HOME\.chefvm"

function Get-ChefVM {
  if ($ChefConfigDir = Get-Item $ChefDir -ErrorAction:SilentlyContinue) {
    if ($ChefConfigDir.LinkType -eq 'SymbolicLink') {
      $ChefDirTarget = $ChefConfigDir.Target
      if ($ChefVMCurrentDir = Get-Item $ChefDirTarget -ErrorAction:SilentlyContinue) {
            $ChefVMCurrentDir
      }
      else {
        Write-Warning "$ChefDirTarget not found"
      }
    }
    else {
      Write-Warning "$ChefDir is not a symbolic link"
    }
  }
  else {
    Write-Warning "$ChefDir not found"
  }
}

function Set-ChefVM {
  param (
    [Parameter(Mandatory = $true)]
    [ArgumentCompleter( {
        param ( $commandName,
          $parameterName,
          $wordToComplete,
          $commandAst,
          $fakeBoundParameters )
        if (Test-Path $ChefVMDir) {
                (Get-ChildItem $ChefVMDir -Directory -Filter "$wordToComplete*").BaseName
        }
      } )]
    [String]
    $ChefVMConfigName
  )

  $ErrorActionPreference = 'Stop'

  if ($ChefConfigDir = Get-Item $ChefDir -ErrorAction:SilentlyContinue) {
    if ($ChefConfigDir.LinkType -eq 'SymbolicLink') {
      $ChefConfigDir.Delete()
    }
    else {
      Write-Warning "$ChefConfigDir is not a symlink. Please delete or rename it and then re-run the command `Set-ChefVM -ChefVMConfigName $ChefVMConfigName`."
    }
  }
  if (-not(Test-Path $ChefDir)) {
    & cmd.exe /c mklink /D "$ChefDir" "$ChefVMDir\configurations\$ChefVMConfigName"
  }

}
