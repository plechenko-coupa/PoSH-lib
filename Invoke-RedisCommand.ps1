function Read-RespResponse {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [String]
    $RespResponse
  )

  function ParseRespResponse([String]$RespResponse = '') {
    $RespSeparator = "`r`n"
  
    if ($RespResponse.Length -gt 2) {
      $RespType, $RespData = $RespResponse[0], $RespResponse.Substring(1).TrimEnd($RespSeparator)
      switch ($RespType) {
        '-' { 
          $cur, $next = $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
          $null, $next
          Write-Error $cur
        }
        '+' { 
          $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
        }
        ':' { 
          $res, $next = $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
          [int]$res, $next
        }
        '$' { 
          $RespBSLength, $RespBSValue = $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
          if ($RespBSLength -eq '-1') {
            $null, $RespBSValue
          }
          elseif ($RespBSValue.Length -gt $RespBSLength) {
            $RespBSValue.Substring(0, $RespBSLength), $RespBSValue.Substring($RespBSLength).TrimStart($RespSeparator)
          }
          else {
            $RespBSValue, ''
          }
        }
        '*' {
          $RespArrayLength, $RespArrayValue = $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)

          $result = @()
          (1..[int]$RespArrayLength) | ForEach-Object {
            $res, $RespArrayValue = ParseRespResponse $RespArrayValue.TrimStart($RespSeparator)
            $result += ,$res
          }
          $result, $RespArrayValue
        }
        Default { 
          $null, ''
          Write-Error "Unknown RESP Data Type: '$RespType'"
        }
      }
    }
  }

  $res, $null = ParseRespResponse $RespResponse
  $res

}

function Invoke-RedisCommand {
  [CmdletBinding()]
  param(
    [String]
    $RedisServer = 'localhost',
    [Parameter(Mandatory = $true)]
    [String]
    $RedisCommand, 
    [int]
    $ResponseTimeoutMs = 1000, 
    [switch]
    $ArrayAsHashtable)
  
  $RedisHost, $RedisPort = $RedisServer -split ':', 2
  if ("$RedisPort" -eq '') { $RedisPort = 6379 }
  Write-Verbose "Connecting to Redis server $RedisHost port $RedisPort"
  try {
    $RedisClient = [System.Net.Sockets.TcpClient]::new( $RedisHost, $RedisPort )
    Write-Verbose "Connected to Redis server $RedisHost port $RedisPort"

    $RespStream = $RedisClient.GetStream( )
    $RespWriter = New-Object System.IO.StreamWriter( $RespStream )
    $RespBuffer = New-Object System.Byte[] 1024
    $Encoding = New-Object System.Text.AsciiEncoding  
  
    Write-Verbose "Sending command '$RedisCommand'"
    $RespWriter.WriteLine($RedisCommand)
    $RespWriter.Flush()

    $tryCounter = $ResponseTimeoutMs
    do {
      Start-Sleep -m 1
    } until ( $RespStream.DataAvailable -or $tryCounter-- -eq 0)

    $RespResponse = ''
    while ( $RespStream.DataAvailable ) {
      $RespData = $RespStream.Read( $RespBuffer, 0, 1024 )
      $RespResponse += $Encoding.GetString( $RespBuffer, 0, $RespData )
    }

    if ($RespResponse -ne '') {

      $ParsedResponse = Read-RespResponse $RespResponse

      if ($ArrayAsHashtable -and $null -ne $ParsedResponse -and $ParsedResponse.GetType().IsArray -and $ParsedResponse.Count -ge 2 -and $ParsedResponse.Count % 2 -eq 0) {
        $Result = @{}

        foreach ($i in 0..($ParsedResponse.count / 2 - 1)) {
          $Result[$ParsedResponse[$i * 2]] = $ParsedResponse[$i * 2 + 1]
        }
        $Result
      }
      else {
        $ParsedResponse
      }
    }
    else {
      Write-Error "Didn't receive any response within ${ResponseTimeoutMs}ms."
    }
  }
  catch {
    throw $_
  }
  finally {
    if ($RespWriter) { $RespWriter.Close( )	}
    if ($RespStream) { $RespStream.Close( )	}
    if ($RedisClient) { 
      $RedisClient.Close() 
      Write-Verbose "Disconnected from Redis server $RedisHost port $RedisPort"
    }
  }   
}


function Test-Read-RespResponse {

#Arrays of arrays
  $rsp = @'
*4
*3
:1
+2aaa
:3
*2
+Hello
+World
$13
qwe
rty
123
-I am an Error
'@
  
  $resp = Read-RespResponse $rsp -ErrorAction:SilentlyContinue -ErrorVariable err
  if ($null -eq $resp) {
    Write-Error 'Should return non-null value'
  }
  if ($resp.GetType().IsArray -eq $false) {
    Write-Error "Resp should be an array"
  }
  if ($resp.Count -ne 4) {
    Write-Error "Size of resp should be 4 but received $($resp.Count)"
  }
  if ($resp[0].GetType().IsArray -eq $false) {
    Write-Error "Resp[0] should be an array"
  }
  if (($resp[0] -join "`n`r") -ne (1,'2aaa',3  -join "`n`r")) {
    Write-Error "Resp[0] should be an array of (1,2aaa,3) but received: ($($resp[0] -join ','))"
  }

  if ($resp[1].GetType().IsArray -eq $false) {
    Write-Error "Resp[1] should be an array"
  }
  if (-join $resp[1] -ne 'HelloWorld') {
    Write-Error "Resp[1] should be 'HelloWorld' but received: '$(-join $resp[1])'"
  }
  if ($resp[2].GetType().IsArray -eq $true) {
    Write-Error "Resp[2] should not be an array"
  }

  if (($resp[2]  -replace "`r",'') -ne "qwe`nrty`n123") {
    Write-Error "Resp[2] should be 'qwe\nrty\n123' but received: '$($resp[2] -replace "`r","\r" -replace "`n","\n")'"
  }  

  if ($null -eq $err -and $err.Count -gt 0) {
    Write-Error 'Should raise error'
  }
  if ($err[0].Exception.Message -ne 'I am an Error') {
    Write-Error "Should raise error with message 'I am an Error' but received '$($err.Exception.Message)'"
  }

}

# Test-Read-RespResponse
