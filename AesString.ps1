function New-AesManagedObject($key, $IV) {
  $aesManaged = New-Object "Security.Cryptography.AesCryptoServiceProvider"
  $aesManaged.Mode = [Security.Cryptography.CipherMode]::CBC
  $aesManaged.BlockSize = 128
  $aesManaged.KeySize = 256
  if ($IV) {
    if ($IV -is "String") {
      $aesManaged.IV = [Convert]::FromBase64String($IV)
    }
    else {
      $aesManaged.IV = $IV
    }
  }
  if ($key) {
    if ($key -is "String") {
      $aesManaged.Key = [Convert]::FromBase64String($key)
    }
    else {
      $aesManaged.Key = $key
    }
  }
  $aesManaged
}

function New-AesKey {
  try {
    $aesManaged = New-AesManagedObject
    $aesManaged.GenerateKey()
    [Convert]::ToBase64String($aesManaged.Key)
  }
  finally {
    if ($aesManaged) { $aesManaged.Dispose() }
  }
}

function ConvertTo-AesString($key, $unencryptedString) {
  try {
    $aesManaged = New-AesManagedObject $key
    $encryptor = $aesManaged.CreateEncryptor()
    $bytes = [Byte[]][Char[]]$unencryptedString
    $encryptedData = $encryptor.TransformFinalBlock($bytes, 0, $bytes.Length)
    [Byte[]] $fullData = $aesManaged.IV + $encryptedData
    [Convert]::ToBase64String($fullData)
  }
  finally {
    if ($aesManaged) { $aesManaged.Dispose() }
  }
}

function ConvertFrom-AesString($key, $encryptedStringWithIV) {
  try {
    $bytes = [Convert]::FromBase64String($encryptedStringWithIV)
    $IV = $bytes[0..15]
    $aesManaged = New-AesManagedObject $key $IV
    $decryptor = $aesManaged.CreateDecryptor()
    $unencryptedData = $decryptor.TransformFinalBlock($bytes, 16, $bytes.Length - 16)
    ( -join [Char[]]$unencryptedData).Trim([Char]0)
  }
  finally {
    if ($aesManaged) { $aesManaged.Dispose() }
  }
}
