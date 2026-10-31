$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$argsList=@('-batch','-prj_path',"$root/td_project",'-prj_name','voice_key4',
    '-ps_path',"$root/user_source/ip_source/MCU",'-design_path',"$root/user_source/ip_source/MCU/Design.xml",
    '-ip_catalog','D:/Anlogic/TD_6.2.1/ip/depot','-model_id','PH1P35MDG324','-bitstream_status','0')
& 'D:\Anlogic\TD_6.2.1\bin\hpfTool.exe' @argsList
if($LASTEXITCODE -ne 0 -or !(Test-Path "$root/td_project/voice_key4.hpf")){throw 'HPF export failed'}
