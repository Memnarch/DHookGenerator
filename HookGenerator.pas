unit HookGenerator;

interface

uses
  Generics.Collections, Classes, Types, SysUtils;

type
  TMethodType = (mtFunction, mtProcedure);

  TInterfaceMethod = class
  private
    FName: string;
    FParameterHeader: string;
    FReturnType: string;
    FMethodType: TMethodType;
  public
    property MethodType: TMethodType read FMethodType write FMethodType;
    property Name: string read FName write FName;
    property ParameterHeader: string read FParameterHeader write FParameterHeader;
    property ReturnType: string read FReturnType write FReturnType;
  end;

  TInterfaceHook = class
  private
    FName: string;
    FStartIndex: Integer;
    FParentName: string;
    FMethods: TObjectList<TInterfaceMethod>;
  public
    constructor Create();
    destructor Destroy(); override;
    property Methods: TObjectList<TInterfaceMethod> read FMethods;
    property Name: string read FName write FName;
    property ParentName: string read FParentName write FParentName;
    property StartIndex: Integer read FStartIndex write FStartIndex;
  end;

  THookGenerator = class
  private
    FInterfaces: TObjectList<TInterfaceHook>;
    FFile: TStringList;
    function IsInterfaceHeader(AIndex: Integer): Boolean;
    function ReadInterface(AIndex: Integer): Integer;
    function GetParentClassName(AInterface: TInterfaceHook): string;
    procedure GetParameterNames(const AHeader: string; ANames: TStringList);
    procedure WriteFieldValues(AInterface: TInterfaceHook);
    procedure WriteMethodDummies(AInterface: TInterfaceHook);
    procedure WriteMethodImplementations(AInterface: TInterfaceHook);
    procedure WriteConstructorImplementation(AInterface: TInterfaceHook);
    procedure WriteHookCode(AInterface: TInterfaceHook);
    procedure ReadInterfaceMethod(const ALine: string; AInterface: TInterfaceHook);
    procedure GeneradeUnitInterface();
    procedure GenerateUnitImplementation();
  public
    constructor Create();
    destructor Destroy(); override;
    procedure LoadFromFile(const AFileName: string);
    procedure SaveToFile(const AFileName: string);
  end;

implementation

uses
  StrUtils;

{ TInterfaceHook }

constructor TInterfaceHook.Create;
begin
  inherited;
  FMethods := TObjectList<TInterfaceMethod>.Create();
end;

destructor TInterfaceHook.Destroy;
begin
  FMethods.Free;
  inherited;
end;

{ THookGenerator }

constructor THookGenerator.Create;
begin
  inherited;
  FInterfaces := TObjectList<TInterfaceHook>.Create();
  FFile := TStringList.Create();
end;

destructor THookGenerator.Destroy;
begin
  FInterfaces.Clear;
  FFile.Free;
  inherited;
end;

procedure THookGenerator.GeneradeUnitInterface;
var
  LInterface: TInterfaceHook;
begin
  FFile.Add('type');
  for LInterface in FInterfaces do
  begin
    FFile.Add('  THook' + LInterface.Name + ' = class(' + GetParentClassName(LInterface) + ')');
    FFile.Add('  private');
    WriteFieldValues(LInterface);
    FFile.Add('  protected');
    WriteMethodDummies(LInterface);
    FFile.Add('  public');
    FFile.Add('    constructor Create(AInstance: ' + LInterface.Name + '); reintroduce;');
    FFile.Add('  end;');
    FFile.Add('');
  end;
end;

procedure THookGenerator.GenerateUnitImplementation;
var
  LInterface: TInterfaceHook;
begin
  for LInterface in FInterfaces do
  begin
    WriteConstructorImplementation(LInterface);
    FFile.Add('');
    WriteMethodImplementations(LInterface);
  end;
end;

procedure THookGenerator.GetParameterNames(const AHeader: string;
  ANames: TStringList);
var
  LNames: TStringDynArray;
  LName, LTName: string;
  LSeperatorPos, LSpacePos: Integer;
begin
  LNames := SplitString(AHeader, ';');
  for LName in LNames do
  begin
    LTName := Trim(LName);
    LSpacePos := Pos(' ', LTName);
    if LSpacePos < 1 then
    begin
      LSpacePos := 1;
    end;
    LSeperatorPos := Pos(':', LTName);
    if LSpacePos > LSeperatorPos then
    begin
      LSpacePos := 1;
    end;
    ANames.Add(Copy(LTName, LSpacePos, LSeperatorPos - LSpacePos));
  end;
end;

function THookGenerator.GetParentClassName(AInterface: TInterfaceHook): string;
begin
  if AnsiIndexText(AInterface.ParentName, ['IInterface', 'IUnknown', 'IDispatch']) >= 0 then
  begin
    Result := 'TObject';
  end
  else
  begin
    Result := 'THook' + AInterface.ParentName;
  end;
end;

function THookGenerator.IsInterfaceHeader(AIndex: Integer): Boolean;
var
  LText: string;
begin
  LText := Trim(FFile[AIndex]);
  Result := StartsText('i', LText) and ContainsText(LText, '= interface');
end;

procedure THookGenerator.LoadFromFile(const AFileName: string);
var
  LIndex: Integer;
begin
  FFile.LoadFromFile(AFileName);
  LIndex := 0;
  while LIndex < FFile.Count do
  begin
    if IsInterfaceHeader(LIndex) then
    begin
      LIndex := ReadInterface(LIndex);
    end;
    Inc(LIndex);
  end;
end;

function THookGenerator.ReadInterface(AIndex: Integer): Integer;
var
  LHeader, LName, LParent: string;
  LPos, LEndPos: Integer;
  LInterface: TInterfaceHook;
  LLine: string;
begin
  LHeader := Trim(FFile[AIndex]);
  LPos := Pos('=', LHeader);
  LName := Trim(Copy(LHeader, 1, LPos -1));
  LPos := Pos('(', LHeader);
  if LPos > 0 then
  begin
    LEndPos := Pos(')', LHeader);
    LParent := Trim(Copy(LHeader, LPos + 1, LEndPos - LPos - 1));
  end
  else
  begin
    LParent := 'IInterface';
  end;
  LInterface := TInterfaceHook.Create();
  LInterface.Name := LName;
  LInterface.ParentName := LParent;
  FInterfaces.Add(LInterface);
  Result := AIndex;
  repeat
    Inc(Result);
    LLine := Trim(FFile[Result]);
    if StartsText('function', LLine) or StartsText('procedure', LLine) then
    begin
      ReadInterfaceMethod(LLine, LInterface);
    end;
  until StartsText('end;', LLine);
  
end;

procedure THookGenerator.ReadInterfaceMethod(const ALine: string;
  AInterface: TInterfaceHook);
var
  LMethod: TInterfaceMethod;
  LLine: string;
  LFirstSpace, LOpen, LClose, LSemicola, LContinue, LSeperator: Integer;
begin
  LLine := ALine;
  LMethod := TInterfaceMethod.Create();
  try
    if StartsText('function', LLine) then
    begin
      LMethod.MethodType := mtFunction;
    end
    else
    begin
      LMethod.MethodType := mtProcedure;
    end;
    LFirstSpace := Pos(' ', LLine);
    LOpen := Pos('(', LLine);
    LClose := Pos(')', LLine);
    LSemicola := Pos(';', LLine);
    LSeperator := Pos(':', LLine);
    LContinue := 1;
    //read methodname
    if LOpen > 0 then
    begin
      LMethod.Name := Trim(Copy(LLine, LFirstSpace + 1, LOpen - LFirstSpace - 1));
      LMethod.ParameterHeader := Trim(Copy(LLine, LOpen + 1, LClose - LOpen - 1));
      LContinue := LClose;
    end
    else
    begin
      //procedure without ()
      if LMethod.MethodType = mtProcedure then
      begin
        LMethod.Name := Trim(Copy(LLine, LFirstSpace + 1, LSemicola - LFirstSpace - 1));
      end
      else
      begin
        //function without () so just name: type
        LMethod.Name := Trim(Copy(LLine, LFirstSpace + 1, LSeperator - LFirstSpace - 1));
        LContinue := LSeperator;
      end;
    end;

    //read functiontype if required
    if LMethod.MethodType = mtFunction then
    begin
      LSeperator := PosEx(':', LLine, LContinue);
      LSemicola := PosEx(';', LLine, LContinue);
      LMethod.ReturnType := Trim(Copy(LLine, LSeperator + 1, LSemicola - LSeperator - 1));
    end;
  finally
    AInterface.Methods.Add(LMethod);
  end;
end;

procedure THookGenerator.SaveToFile(const AFileName: string);
begin
  FFile.Clear;
  FFile.Add('unit ' + ChangeFileExt(ExtractFileName(AFileName), ''));
  FFile.Add('');
  FFile.Add('interface');
  GeneradeUnitInterface();
  FFile.Add('');
  FFile.Add('implementation');
  FFile.Add('');
  GenerateUnitImplementation();
  FFile.Add('end.');
  FFile.SaveToFile(AFileName);
end;

procedure THookGenerator.WriteConstructorImplementation(
  AInterface: TInterfaceHook);
begin
  FFile.Add('constructor THook' + AInterface.Name + '.Create( AInstance: ' + AInterface.Name + ');');
  FFile.Add('begin');
  if not SameText(GetParentClassName(AInterface), 'TObject') then
  begin
    FFile.Add('  inherited Create(AInstance as ' + AInterface.ParentName + ');');
  end
  else
  begin
    FFile.Add('  inherited');
  end;
  WriteHookCode(AInterface);
  FFile.Add('end;');
end;

procedure THookGenerator.WriteFieldValues(AInterface: TInterfaceHook);
var
  LLine: string;
  LMethod: TInterfaceMethod;
begin
  for LMethod in AInterface.Methods do
  begin
    if LMethod.MethodType = mtProcedure then
    begin
      LLine := 'procedure';
    end
    else
    begin
      LLine := 'function';
    end;
    LLine := LLine  + '(Instance: Pointer';
    if LMethod.ParameterHeader <> '' then
    begin
     LLine := LLine + '; ' + LMethod.ParameterHeader;
    end;
    LLine := LLine + ')';
    if LMethod.MethodType = mtFunction then
    begin
      LLine := LLine + ': ' + LMethod.ReturnType;
    end;
    LLine := LLine + ';';
    FFile.Add('    F' + LMethod.Name + ': ' + LLine);
  end;
end;

procedure THookGenerator.WriteHookCode(AInterface: TInterfaceHook);
var
  LMethod: TInterfaceMethod;
  LIndex: Integer;
begin
  LIndex := AInterface.StartIndex;
  for LMethod in AInterface.Methods do
  begin
    FFile.Add('  IntRefToMethPtr(AInstance, F' + LMethod.Name + ', ' + IntToStr(LIndex) + ');');
    FFile.Add('  @F' + LMethod.Name + ' := InterceptCreate(@F' + LMethod.Name + ', @THook' + AInterface.Name + '.' + LMethod.Name + ');');
    Inc(LIndex);
  end;
end;

procedure THookGenerator.WriteMethodDummies(AInterface: TInterfaceHook);
var
  LLine: string;
  LMethod: TInterfaceMethod;
begin
  for LMethod in AInterface.Methods do
  begin
    if LMethod.MethodType = mtFunction then
    begin
      LLine := '    function ';
    end
    else
    begin
      LLine := '    procedure ';
    end;
    LLine := LLine + LMethod.Name + '(' + LMethod.ParameterHeader + ')';
    if LMethod.MethodType = mtFunction then
    begin
      LLine := LLine + ': ' + LMethod.ReturnType;
    end;
    FFile.Add(LLine + ';')
  end;
end;

procedure THookGenerator.WriteMethodImplementations(AInterface: TInterfaceHook);
var
  LMethod: TInterfaceMethod;
  LLine, LName: string;
  LNames: TStringList;
begin
  LNames := TStringList.Create();
  for LMethod in AInterface.Methods do
  begin
    LNames.Clear();
    GetParameterNames(LMethod.ParameterHeader, LNames);
    if LMethod.MethodType = mtProcedure then
    begin
      LLine := 'procedure ';
    end
    else
    begin
      LLine := 'function ';
    end;
    LLine := LLine + 'THook' + AInterface.Name + '.' + LMethod.Name + '(' + LMethod.ParameterHeader + ')';
    if LMethod.MethodType = mtFunction then
    begin
      LLine := LLine + ': ' + LMethod.ReturnType;
    end;
    LLine := LLine + ';';
    FFile.Add(LLine);

    FFile.Add('begin');
    if LMethod.MethodType = mtFunction then
    begin
      LLine := '  Result := F';
    end
    else
    begin
      LLine := '  F';
    end;
    LLine := LLine + LMethod.Name + '(Self';
    for LName in LNames do
    begin
      LLine := LLine + ', ' + LName;
    end;
    LLine := LLine + ');';
    FFile.Add(LLine);
    FFile.Add('end;');
    FFile.Add('');
  end;
  LNames.Free;
end;

end.
