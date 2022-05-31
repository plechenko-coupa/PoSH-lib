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
          $null, ''
          Write-Error $RespData 
        }
        '+' { 
          $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
        }
        ':' { 
          $RespData.Split($RespSeparator, 2, [System.StringSplitOptions]::RemoveEmptyEntries)
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

          $result = (1..[int]$RespArrayLength) | ForEach-Object {
            $res, $RespArrayValue = ParseRespResponse $RespArrayValue.TrimStart($RespSeparator)
            $res
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
      Write-Error "Didn't receive any responce within ${ResponseTimeoutMs}ms."
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
