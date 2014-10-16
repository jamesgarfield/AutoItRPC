#include <AutoItConstants.au3>
#include <Array.au3>

Const $AUTOIT_RPC_VERSION = "0.1.0"

Const $STX = Chr(2)                     ;Start of Text (array open)
Const $ETX = Chr(3)                     ;End Of Text (array terminator)
Const $ENQ = Chr(5)                     ;Enquiry (Ping)
Const $ACK = Chr(6)                     ;Acknowledge (Ping)
Const $FS = Chr(28)                     ;File Separator (command message length / message separator)
Const $GS = Chr(29)                     ;Group Separator (command group command / args separator)
Const $RS = Chr(30)                     ;Record Separator (array entry separator)
Const $US = Chr(31)                     ;Unit separator (value type / data  separator)

Const $MAX_MESSAGE_LENGTH = 16777216    ;Max array length

Global Enum $ERROR_NONE, _
            $ERROR_SOCKET, _
            $ERROR_INVALID_MESSAGE_LENGTH, _
            $ERROR_MESSAGE_TOO_BIG, _
            $ERROR_INVALID_ARRAY_FORMAT, _
            $ERROR_INVALID_VALUE_TYPE, _
            $ERROR_INVALID_VALUE, _
            $ERROR_UNREGISTERED_VALUE_TYPE

Main()

Func Main()
    Serve("127.0.0.1", 6542)
EndFunc

Func Serve($ip, $port)
    OnAutoItExitRegister(OnExit)
    TCPStartup()
    Local $listenSocket = TCPListen($ip, $port, 100)
    Local $err = 0

    If @error Then
        ERR(@error, "Launch error on " & $ip & ":" & String($port))
		Return
    EndIf
    DBG("Serving on " & $ip & ":" & String($port))

    Local $client = 0
    Local $message = ""
    Local $result = ""
    Local $connected = False
    While True
        $client = GetClientConnection($listenSocket)
        If @error Then
		   ERR(@error)
		   $connected = False
		   ContinueLoop
	   EndIf

        $connected = True

        While $connected
            $message = ReadMessagePacket($client)
            If @error Then
                ERR(@error)
                $connected = False
            EndIf

            If ($message == Null) Then
                ContinueLoop
            EndIf

            $result = ProcessCommand($message)
            If @error Then
                ERR(@error)
            EndIf
            DBG(String($result))
            DBG("----")
            ConsoleWrite($result)
            SendResult($client, $result)
        WEnd

    WEnd
EndFunc

#cs
 Poll for an incoming client connection

 @param {Socket} $listenSocket

 @return {Socket} Client socket

 @throws {ERR_SOCKET}
#ce
Func GetClientConnection($listenSocket)
    Local $socket = 0
    Do
        $socket = TCPAccept($listenSocket)
        If @error Then
            SetError($ERROR_SOCKET)
            Return Null
        EndIf
    Until $socket <> -1
    Return $socket
EndFunc

#cs
 Read a message packet from a given client

 @param {Socket} $client

 @return {String} Message from the packet

 @throws {ERR_MESSAGE_TOO_BIG}
 @throws {ERR_INVALID_MESSAGE_LENGTH}
 @throws {ERR_SOCKET}
#ce
Func ReadMessagePacket($client)
    Local $message_length = ReadMessageLength($client)
    If @error Then
        Return Null
    EndIf
    DBG("Message Length: " & String($message_length))
    Local $message = ReadMessage($client, $message_length)
    If @error Then
        SetError(@error)
        Return Null
    EndIf
    DBG("Message: " & String($message))
    Return $message
EndFunc

#cs
 Read the message length segment of a message packet

 @param {Socket} $client

 @return {Int}

 @throws {ERR_MESSAGE_TOO_BIG}
 @throws {ERR_INVALID_MESSAGE_LENGTH}
 @throws {ERR_SOCKET}
#ce
Func ReadMessageLength($client)
    Local $raw = ""
    Local $char = ""

    ; RPC Message Structure
    ; -------------------------------
    ;| message_length | FS | message |
    ; -------------------------------

    For $i = 1 to StringLen(String($MAX_MESSAGE_LENGTH))
        $char = TCPRecv($client, 1)                     ;Read one character

        If @error Then
            SetError($ERROR_SOCKET)
            Return Null
        EndIf

        If ( $char == $FS ) Then                   ;Segment terminator, stop reading
            Local $length = Int($raw)
            If ($length > $MAX_MESSAGE_LENGTH) Then
                SetError($ERROR_MESSAGE_TOO_BIG)
                Return Null
            EndIf
            Return $length
        EndIf

        If ( Not StringIsInt($char) ) Then              ;Character must be an integer
            SetError($ERROR_INVALID_MESSAGE_LENGTH)
            Return Null
        EndIf

        $raw = $raw & $char
    Next

    ;Valid message lengths should terminate in the loop
    SetError($ERROR_INVALID_MESSAGE_LENGTH)
    Return Null
EndFunc

#cs
 Read the message segment of a message packet

 @param {Socket} $client
 @param {Int} @length

 @return {String}

 @throws {ERR_MESSAGE_TOO_BIG}
 @throws {ERR_SOCKET}
#ce
Func ReadMessage($client, $length)
    If ($length > $MAX_MESSAGE_LENGTH) Then
        SetError($ERROR_MESSAGE_TOO_BIG)
        Return Null
        EndIf

    $message = TCPRecv($client, $length)

    If @error Then
        SetError($ERROR_SOCKET)
        Return Null
    EndIf

    Return $message
EndFunc

Func StringIterable($str)
    Local $data = StringSplit($str, "")
    Local $iter[] = [0, $data[0], $data]
    Return $iter
EndFunc

Func GetNext(ByRef $iter)
    If Not HasNext($iter) Then
        Return Null
    EndIf

    Local $index = $iter[0] + 1
    $iter[0] = $index

    Local $data = $iter[2]
    Local $val = $data[$index]
    Return $val
EndFunc

Func HasNext(ByRef $iter)
    Local $index = $iter[0]
    Local $max = $iter[1]
    Return $index < $max
EndFunc

#cs
 Process the execution of a given command message

 @param {String} $message

 @return {String}
#ce
Func ProcessCommand($message)
    Local $iter = StringIterable($message)
    Local $command = ParseCommand($iter)
    Local $args = ParseArguments($iter)
    If @error Then
        ERR(@error)
        Return Null
    EndIf

    DBG($command)

    Local $result

    If ( $args == Null ) Then
        $result = Call($command)
    Else
        $result = Call($command, $args)
    EndIf

    If @error Then
        ERR(@error)
        Return Null
    EndIf

    Return $result
EndFunc

Func SendResult($client, $result)
    Local $str = SerializeValue($result)
    TCPSend($client, $str)
EndFunc

Func ParseCommand(ByRef $iter)
    Local $char = ""
    Local $command = ""

    ; message layout
    ; ---------------------
    ;| command | GS | args |
    ; ---------------------
    While HasNext($iter)
        $char = GetNext($iter)
        Switch $char
            Case $GS
                Return $command

            Case Else
                $command = $command & $char
        EndSwitch
    WEnd
    Return $command
EndFunc

Func ParseArguments(ByRef $iter)
    If HasNext($iter) Then
        Return ParseArray($iter, true)
    EndIf
    Return Null ;No arguments passed
EndFunc

Func ParseArray(ByRef $iter, $is_call_args)
    DBG("Parsing Array...")
    Local $char = ""

    ; Array Layout
    ; ---------------------------------------------
    ;| STX | value | RS | value | RS | value | ETX |
    ; ---------------------------------------------


    $char = GetNext($iter)
    If ($char <> $STX) Then
        SetError($ERROR_INVALID_ARRAY_FORMAT)
        Return Null
    EndIf

    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------



    Local $a[10]
    Local $size = 10
    Local $pos = 0

    If ( $is_call_args == true ) Then
        $a[0] = "CallArgArray"
        $pos = 1
    EndIf

    Local $value
    While HasNext($iter)
        $value = ParseValue($iter)

        If @error Then
            Return Null
        EndIf

        If ($pos == $size) Then     ;Array too small to add to, increase size
            $size = $size * 2
            ReDim $a[$size]
        EndIf
        $a[$pos] = $value
        $pos = $pos + 1

        Switch GetNext($iter)
            Case $RS
                ContinueLoop

            Case $ETX
                If ($pos < $size) Then  ;Shrink array back down to its final size
                    ReDim $a[$pos]
                EndIf
                Return $a

            Case Else
                SetError($ERROR_INVALID_ARRAY_FORMAT)
                Return Null
        EndSwitch
    Wend
EndFunc

Func ParseValue(ByRef $iter)
    DBG("Parsing Value...")
    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------

    Local $type = ParseValueType($iter)

    If @error Then
        Return Null
    EndIf

    DBG("Type: " & $type)

    ;Arrays are a special parsing case
    If ( $type == "arr" ) Then
        Return ParseArray($iter, false)
    EndIf

    Local $data = ParseValueData($iter)

    DBG("(" & $type & ") " & $data)

    Switch $type
        Case "i32"
            Return Int($data, 1)

        Case "i64"
            Return Int($data, 2)

        Case "num"
            Return Number($data)

        Case "bool"
            Return $data == "true"

        Case "hwnd"
            Return HWnd($data)

        Case "str"
            Return $data

        Case Else
            SetError($ERROR_UNREGISTERED_VALUE_TYPE)
            Return Null
    EndSwitch
EndFunc

Func ParseValueType(ByRef $iter)
    Local $char = ""
    Local $type = ""

    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------

    $char = GetNext($iter)

    If ($char <> $STX) Then
        SetError($ERROR_INVALID_VALUE_TYPE)
        Return Null
    EndIf


    While HasNext($iter)
        $char = GetNext($iter)
        Switch $char
            Case $US
                return $type

            Case Else
                $type = $type & $char
		 EndSwitch
    WEnd
    SetError($ERROR_INVALID_VALUE_TYPE)
    Return Null
EndFunc

Func ParseValueData(ByRef $iter)
    Local $char = ""
    Local $data = ""

    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------
    While HasNext($iter)
        $char = GetNext($iter)
        Switch $char
            Case $ETX                   ;End of data
                Return $data
            Case Else
                $data = $data & $char
		 EndSwitch
    WEnd
    SetError($ERROR_INVALID_VALUE_TYPE)
    Return Null
EndFunc

Func SerializeArray(Const ByRef $a)
    ;Array Format (arr)
    ; ---------------------------------------------
    ;| STX | value | RS | value | RS | value | ETX |
    ; ---------------------------------------------
    DBG(_ArrayToString($a, $ETX & $STX, 0, 0, $RS))
    Local $str = $STX
    Switch UBound($a, $UBOUND_DIMENSIONS)
        Case 1
            $str = $str & SerializeSingleArray($a)

        Case 2
            $str = $str & SerializeDoubleArray($a)
    EndSwitch
    $str = $str & $ETX

    Return $str

EndFunc

Func SerializeSingleArray(Const ByRef $a)
    Local $str = ""
    For $i = 0 To UBound($a)
        $str = $str & SerializeValue($a[$i])
        If @error Then
            ERR(@error, "Serializing array value")
            Return Null
        EndIf
    Next
    Return $str
EndFunc

Func SerializeDoubleArray(Const ByRef $a)
    Local $str = ""
	Local $end_col = UBound($a, $UBOUND_COLUMNS) - 1
	Local $end_row = UBound($a, $UBOUND_ROWS) - 1
    For $i = 0 To $end_row
        For $j = 0 To $end_col
            $str = $str & SerializeValue($a[$i][$j])
            If @error Then
              ERR(@error, "Serializing array value")
             Return Null
            EndIf
        Next
    Next
    Return $str
EndFunc

Func SerializeValue(Const ByRef $v)
    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------
    If IsArray($v) Then
        Return WrapValueType("arr", SerializeArray($v))
    ElseIf IsBool($v) Then
        If $v Then
            Return WrapValueType("bool", "1")
        Else
            Return WrapValueType("bool", "0")
        EndIf
    ElseIf IsHWnd($v) Then
        Return WrapValueType("hwnd", String($v))
    ElseIf IsNumber($v) Then
        If IsInt($v) Then
            Return WrapValueType("i32", String($v))
        Else
            Return WrapValueType("num", String($v))
        EndIf
    ElseIf IsString($v) Then
        Return WrapValueType("str", $v)
    Else
        SetError($ERROR_UNREGISTERED_VALUE_TYPE)
        Return Null
    EndIf
EndFunc

Func WrapValueType($type, $val)
    ;Value Format
    ; ------------------------------
    ;| STX | type | US | data | ETX |
    ; ------------------------------
    Return $STX & $type & $US & $val & $ETX
EndFunc

Func ERR($err, $msg="")
    Local $type = "Undefined Error"
    Switch $err
        Case $ERROR_SOCKET
            $type = "Socket Error"
        Case $ERROR_INVALID_MESSAGE_LENGTH
            $type = "Invalid Message Length"
        Case $ERROR_MESSAGE_TOO_BIG
            $type = "Message Too Big"
        Case $ERROR_INVALID_ARRAY_FORMAT
            $type = "Invalid Array Format"
        Case $ERROR_INVALID_VALUE_TYPE
            $type = "Invalid Value Type"
        Case $ERROR_INVALID_VALUE
            $type = "Invalid Value"
        Case $ERROR_UNREGISTERED_VALUE_TYPE
            $type = "Unregistered Value Type"
    EndSwitch
    ConsoleWrite($type & ":" & $err & ". " & $msg & @CR)
    ConsoleWrite("Error: " & $err & @CR)
EndFunc

Func DBG($msg)
    ConsoleWrite($msg & @CR)
EndFunc

Func OnExit()
   TCPShutdown()
EndFunc