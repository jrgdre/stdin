{!  Unified reading from StdIn for MS-Windows.

	@copyright
		(c)2021 Medical Data Solutions GmbH, www.medaso.de

	@license
		MIT:
			Permission is hereby granted, free of charge, to any person
			obtaining a copy of this software and associated documentation files
			(the "Software"), to deal in the Software without restriction,
			including without limitation the rights to use, copy, modify, merge,
			publish, distribute, sublicense, and/or sell copies of the Software,
			and to permit persons to whom the Software is furnished to do so,
			subject to the following conditions:

			The above copyright notice and this permission notice shall be
			included in all copies or substantial portions of the Software.

	@author
		jrgdre: J.Drechsler, Medical Data Solutions GmbH

	@version
		1.0.0 2021-07-08 jrgdre, initial release
}
unit StdIn_Windows;
{$mode Delphi}

interface

{$ifdef Windows}

uses
	classes,
	StdIn;

{!  Append `memory` with the values read from StdIn.

	Works for following use cases:
	1. `prg < file`
	2. `(type, cat) file | prg`
	3. `prg`

	In the first two cases it is assumed, that all the input is in the file.
	The file is read with blocking calls, until the end of the file is reached.

	In the third case the function waits for the user to input the first char.
	If `timeOut` is reached before that, the procedure exits.
	After the first char is read, the routine waits indefinitely for more chars
	to to be entered, until it reads the EOF signal.

	The default value of `0` for `timeOut` makes the procedure wait indefinitely
	also for the first char.

	`timeOut` as a fixed resolution of 50ms.

	@returns TStdInReadError
}
function Windows_Read_StdIn(
	  var ms     : TMemoryStream; //!< target of read operation
	const timeOut: NativeUInt = 0 //!< timeout for first key input (50ms res.)
): TStdInReadError; overload;

{$endif}

implementation

{$ifdef Windows}

uses
	windows,
	sysutils;

{!  Read from a redirected input stream.
}
function ReadFile(
	  var ms: TMemoryStream;
	const h : THandle
): TStdInReadError;
var
	b : Byte;
	hs: THandleStream;
begin
	hs := THandleStream.Create(h);
	if (not Assigned(hs)) then begin
		Result := sireInvalidHandle;
		Exit;
	end;
	try
		if (hs.Size > 0) then begin
			hs.Position := 0;
			while (hs.Position < hs.Size) do begin
				try
					b := hs.ReadByte;
				except
					on E: Exception do begin
						Result := sireReadError;
						Exit;
					end;
				end;
				try
					ms.WriteByte(b);
				except
					on E: Exception do begin
						Result := sireWriteError;
						Exit;
					end;
				end;
			end;
		end;
	finally
		hs.Free;
	end;
	Result := sireNoError;
end;

{!  Read interactive keyboard input, with timeout for first key.

	- For all consecutive keys the function waits indefinitely.
	- Reading the input stops, when the user inputs EOF (CTRL-Z on Windows).

	The global variable `ShowHint` in `Stdin.pas` controls, if the function
	writes `Hint1` and `Hint2` (also global variables in `Stdin.pas`) to the
	console.

	The global variable `TimeOutResolutionMS` in `Stdin.pas` controls the sleep
	time between the checks for the first input.
}
function ReadInteractive(
	  var ms     : TMemoryStream;
	const h      : THandle;
	const timeOut: NativeUInt
): TStdInReadError;
var
	c  : Char;
	cnt: Cardinal;
	ir : TInputRecord;
	ts : QWord;
begin
	if ShowHint then begin
		WriteLn(Format(Hint1, [timeOut]));
		WriteLn(Hint2);
	end;

	cnt := 0;
	ts  := GetTickCount64;
	repeat
		PeekConsoleInput(h, ir, 1, cnt); // non-blocking on windows,
										 // non-redirected stdIn only
		if (cnt = 0) then begin
			Sleep(TimeOutResolutionMS);
			if ((GetTickCount64 - ts) >= timeOut) then begin
				Result := sireTimeOut;
				Exit;
			end;
		end;
	until (cnt > 0);

	while (not EOF) do begin
		c := #0;
		System.Read(c);
		if (ms.Write(c, 1) = 0) then begin
			Result := sireWriteError;
			Exit;
		end;
	end;

	Result := sireNoError;
end;

{
}
function Windows_Read_StdIn(
	  var ms     : TMemoryStream;
	const timeOut: NativeUInt = 0
): TStdInReadError;
var
	h: THandle;
begin
	h  := GetStdHandle(STD_INPUT_HANDLE);
	if (h = 0) then begin
		Result := sireNullHandle;
		Exit;
	end;
	if (h = INVALID_HANDLE_VALUE) then begin
		Result := sireInvalidHandle;
		Exit;
	end;

	case GetFileType(h) of

		FILE_TYPE_DISK, // case `prg < file`
		FILE_TYPE_PIPE: // case `type file | prg`
			Result := ReadFile(ms, h);

		FILE_TYPE_CHAR: // case `prg`
			Result := ReadInteractive(ms, h, timeOut);

		else // unknown file type
			Result := sireSourceErr;

	end;
end;

{$endif}

end.
