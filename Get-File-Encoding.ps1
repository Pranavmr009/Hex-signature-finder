using namespace System.Collections.Generic; using namespace System.Linq

function Get-FileEncoding {
    <#
    .SYNOPSIS
        Attempt to determine a file type based on a BOM or file header.
    .DESCRIPTION
        This script attempts to determine file types based on a byte sequence at the beginning of the file.
        
        If an identifiable byte sequence is not present the file type cannot be determined using this method.

        The order signatures appear in is critical where signatures overlap. For example, UTF32-LE must be evaluated before UTF16-LE. 
    .LINK
        https://en.wikipedia.org/wiki/Byte_order_mark#cite_note-b-15
        https://filesignatures.net
    #>

    [CmdletBinding()]
    [OutputType('EncodingInfo')]
    param (
        # The path to a file to analyze.
        [Parameter(Mandatory, Position = 1, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateScript( { Test-Path $_ -PathType Leaf } )]
        [Alias('FullName')]
        [String]$Path,

        # Test the file against a small set of signature definitions for binary file types.
        #
        # Identification should be treated as tentative. Several file formats cannot be identified using the sequence at the start alone.
        [Switch]$IncludeBinary
    )

    begin {
        $signatures = [Ordered]@{
            'UTF32-LE'   = 'FF-FE-00-00'
            'UTF32-BE'   = '00-00-FE-FF'
            'UTF8'       = 'EF-BB-BF'
            'UTF16-LE'   = 'FF-FE'
            'UTF16-BE'   = 'FE-FF'
            'UTF7'       = '2B-2F-76-38', '2B-2F-76-39', '2B-2F-76-2B', '2B-2F-76-2F'
            'UTF1'       = 'F7-64-4C'
            'UTF-EBCDIC' = 'DD-73-66-73'
            'SCSU'       = '0E-FE-FF'
            'BOCU-1'     = 'FB-EE-28'
            'GB-18030'   = '84-31-95-33'
        }

        if ($IncludeBinary) {
            $signatures += [Ordered]@{
                'LNK'      = '4C-00-00-00-01-14-02-00'
                'MSEXCEL'  = '50-4B-03-04-14-00-06-00'
                'PNG'      = '89-50-4E-47-0D-0A-1A-0A'
                'MSOFFICE' = 'D0-CF-11-E0-A1-B1-1A-E1'
                '7ZIP'     = '37-7A-BC-AF-27-1C'
                'RTF'      = '7B-5C-72-74-66-31'
                'GIF'      = '47-49-46-38'
                'REGPOL'   = '50-52-65-67'
                'GZIP'     = '1F-8B'
                'JPEG'     = 'FF-D8'
                'MSEXE'    = '4D-5A'
                'ZIP'      = '50-4B'
            }
        }

        # Convert sequence strings to byte arrays. Intended to simplify signature maintenance.
        [String[]]$keys = $signatures.Keys
        foreach ($name in $keys) {
            [List[List[Byte]]]$values = foreach ($value in $signatures[$name]) {
                [List[Byte]]$signatureBytes = foreach ($byte in $value.Split('-')) {
                    [Convert]::ToByte($byte, 16)
                }
                ,$signatureBytes
            }
            $signatures[$name] = $values 
        }
    }

    process {
        try {
            $Path = $pscmdlet.GetUnresolvedProviderPathFromPSPath($Path)

            $bytes = [Byte[]]::new(8)
            $stream = [System.IO.File]::OpenRead($Path)
            $null = $stream.Read($bytes, 0, $bytes.Count)
            $bytes = [List[Byte]]$bytes
            $stream.Close()

            $encoding = foreach ($name in $signatures.Keys) {
                $sampleEncoding = foreach ($sequence in $signatures[$name]) {
                    $sample = $bytes.GetRange(0, $sequence.Count)

                    if ([System.Linq.Enumerable]::SequenceEqual($sample, $sequence)) {
                        $name
                        break
                    }
                }
                if ($sampleEncoding) {
                    $sampleEncoding
                    break
                }
            }

            [PSCustomObject]@{
                Name       = Split-Path $Path -Leaf
                Extension  = [System.IO.Path]::GetExtension($Path)
                Encoding   = $encoding
                Path       = $Path
                PSTypeName = 'EncodingInfo'
            }
        } catch {
            $pscmdlet.WriteError($_)
        }
    }
}

