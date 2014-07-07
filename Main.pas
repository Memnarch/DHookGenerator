unit Main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls;

type
  TForm1 = class(TForm)
    Button1: TButton;
    procedure Button1Click(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

uses
  HookGenerator;

{$R *.dfm}

procedure TForm1.Button1Click(Sender: TObject);
var
  LGenerator: THookGenerator;
begin
  LGenerator := THookGenerator.Create();
  try
    LGenerator.LoadFromFile('D:\Program Files (x86)\Embarcadero\RAD Studio\8.0\source\ToolsAPI\ToolsAPI.pas');
    LGenerator.SaveToFile('C:\tmp\Hooked.pas');
  finally

  end;
end;

end.
