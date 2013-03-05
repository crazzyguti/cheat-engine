unit frmMemoryViewExUnit;

{$mode delphi}

interface

uses
  windows, Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, ExtCtrls,
  StdCtrls, ComCtrls, memdisplay, newkernelhandler, cefuncproc, syncobjs, math;

type
  TMemoryDataSource=class(TThread)
  private
    cs: TCriticalSection;
    address: ptruint;
    buf: pbytearray;
    bufsize: integer;
    faddresslistonly: boolean;

    temppagebuf: pbytearray;
  public
    procedure lock;
    procedure unlock;
    procedure setRegion(address: ptruint; buf: pointer; size: integer);
    procedure execute; override;
    procedure fetchmem;
    procedure setaddresslistonly(state: boolean);
    constructor create(suspended: boolean);
    property addresslistonly: boolean read faddresslistonly write setaddresslistonly;
  end;

  { TfrmMemoryViewEx }

  TfrmMemoryViewEx = class(TForm)
    cbAddresslistOnly: TCheckBox;
    CheckBox1: TCheckBox;
    ComboBox1: TComboBox;
    ComboBox2: TComboBox;
    edtPitch: TEdit;
    Label1: TLabel;
    lblAddress: TLabel;
    Label2: TLabel;
    Panel1: TPanel;
    RadioButton1: TRadioButton;
    RadioButton2: TRadioButton;
    RadioButton3: TRadioButton;
    Timer1: TTimer;
    tbPitch: TTrackBar;
    procedure cbAddresslistOnlyChange(Sender: TObject);
    procedure edtPitchChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure tbPitchChange(Sender: TObject);
  private
    { private declarations }
    buf: pbytearray;
    bufsize: integer;
    datasource: TMemoryDataSource;


    function ondata(newAddress: ptruint; PreferedMinimumSize: integer; var newbase: pointer; var newsize: integer): boolean;
  public
    { public declarations }
    md: TMemDisplay;
  end;

var
  frmMemoryViewEx: TfrmMemoryViewEx;

implementation

uses MemoryBrowserFormUnit, MainUnit;

{$R *.lfm}


{ TMemoryDataSource }

constructor TMemoryDataSource.create(suspended: boolean);
begin
  cs:=tcriticalsection.create;

  getmem(temppagebuf, 4096);  //so it doesn't need to be allocated/freed each fetchmem call

  inherited create(suspended);
end;

procedure TMemoryDataSource.setaddresslistonly(state: boolean);
begin
  faddresslistonly:=true;
  fetchmem; //update now
end;

procedure TMemoryDataSource.fetchmem;
var x: dword;
  a: dword;
  s: integer;
begin


  lock;

  if buf<>nil then  //not yet initialized
  begin

    a:=address;


    while a<address+bufsize do
    begin
      s:=min((address+bufsize)-a, 4096-(a mod 4096)); //the number of bytes left in this page or for this buffer

      x:=0;
      if faddresslistonly then
      begin
        //check if this page has any addresses.
        zeromemory(temppagebuf, 4096);



      end
      else
      begin
        ReadProcessMemory(processhandle, pointer(a), @buf[a-address], s, x);
        if x<s then //zero the unread bytes
          zeromemory(@buf[a-address], s-x);
      end;

      a:=a+s; //next page
    end;

  end;
  unlock;
end;

procedure TMemoryDataSource.execute;
begin
  while not terminated do
  begin
    sleep(100);

    fetchmem;
  end;
end;

procedure TMemoryDataSource.lock;
begin
  cs.enter
end;

procedure TMemoryDataSource.unlock;
begin
  cs.leave;
end;

procedure TMemoryDataSource.setRegion(address: ptruint; buf: pointer; size: integer);
begin
  lock;
  self.address:=address;
  self.buf:=buf;
  bufsize:=size;

  fetchmem;
  unlock;


end;

{ TfrmMemoryViewEx }
function TfrmMemoryViewEx.ondata(newAddress: ptruint; PreferedMinimumSize: integer; var newbase: pointer; var newsize: integer): boolean;
var x: dword;
begin

  //todo: Pre-buffer when going up. (allocate 4096 bytes in front, and give a pointer to 4096 bytes after. Only when the newaddress becomes smaller than the base realloc

  label1.caption:=inttohex(newaddress,8);

  datasource.lock;
  if bufsize<PreferedMinimumSize then
  begin
    try
      ReAllocMem(buf, PreferedMinimumSize+4096);
    except
      beep;
    end;

    if buf=nil then
      bufsize:=0
    else
      bufsize:=PreferedMinimumSize+4096;
  end;

  datasource.setRegion(newaddress, buf, bufsize);
  datasource.unlock;


  newbase:=buf;
  newsize:=bufsize;
  result:=newsize>=PreferedMinimumSize; //allow the move if allocated enough memory
end;

procedure TfrmMemoryViewEx.FormCreate(Sender: TObject);
begin
  //create a datasource thread
  datasource:=TMemoryDataSource.create(true); //possible to add multiple readers in the future

  md:=TMemDisplay.Create(self);
  md.onData:=ondata;

  getmem(buf,4096);
  bufsize:=4096;

  datasource.setRegion(MemoryBrowser.hexview.Address and ptruint(not $FFF), buf, bufsize);
  md.setPointer(MemoryBrowser.hexview.Address and ptruint(not $FFF), buf, bufsize);
  md.Align:=alClient;
  md.parent:=panel1;



  datasource.Start;
end;

procedure TfrmMemoryViewEx.edtPitchChange(Sender: TObject);
var newpitch: integer;
begin
  try
    newpitch:=strtoint(edtpitch.Caption);
    md.setPitch(newpitch);
    edtPitch.Font.Color:=clDefault;
  except
    edtPitch.Font.Color:=clred;
  end;
end;

procedure TfrmMemoryViewEx.cbAddresslistOnlyChange(Sender: TObject);
begin
  if datasource<>nil then
    datasource.addresslistonly:=cbAddresslistOnly.checked;
end;

procedure TfrmMemoryViewEx.FormDestroy(Sender: TObject);
begin
  if datasource<>nil then
  begin
    datasource.Terminate;
    datasource.WaitFor;
    freeandnil(datasource);
  end;
end;

procedure TfrmMemoryViewEx.Timer1Timer(Sender: TObject);
begin
  lbladdress.caption:='Address : '+inttohex(md.getTopLeftAddress,8);
end;

procedure TfrmMemoryViewEx.tbPitchChange(Sender: TObject);
begin
  edtPitch.caption:=inttostr(trunc(2**tbPitch.position));
end;

end.
