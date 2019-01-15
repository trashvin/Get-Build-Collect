################################
 # version history            #
 #                            #
 # v1.0 Jan.10.2019 mtrilles  #
################################
param(
    [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$conf
)
Clear-Host

Function Show-Process
{
    Param($s1,$s2);
    Write-Host -join($s1," ") -NoNewline -ForegroundColor Cyan;
    Write-Host $s2 -NoNewline -ForegroundColor DarkYellow;
    Write-Host " ..." -ForegroundColor Cyan;
}
Function Show-Value
{
    Param($s1,$s2);
    Write-Host -join($s1," : ")  -NoNewline -ForegroundColor Yellow ; 
    Write-Host $s2 -ForegroundColor DarkYellow;
}


#read config
$buildConfig = Get-Content $conf |Out-String|ConvertFrom-Json
$completeProjectPath = -join($buildConfig.tfs.project,$buildConfig.tfs.branch);
$log = "build.log";

if(Test-Path -Path $log)
{
    Remove-Item -Recurse -Force $log | Out-Null;   
}

Write-Host "Get-Build-Collect" -ForegroundColor Green;
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Red;
Write-Host "project name : " -NoNewline -ForegroundColor Gray; 
Write-Host $buildConfig.project -ForegroundColor DarkGray;
""
Show-Process("loading build configuration file from ",$conf);
""
Show-Value("server",$buildConfig.system);
Show-Value("operation",$buildConfig.operation);
Show-Value("collection",$buildConfig.tfs.collection);
Show-Value("project",$buildConfig.tfs.project);
Show-Value("branch",$buildConfig.tfs.branch);
Show-Value("workspace",$buildConfig.tfs.workspace);
Show-Value("location",$buildConfig.tfs.location);
""
try 
{
    Write-Host "creating workspace " -NoNewline -ForegroundColor Cyan;
    Write-Host $buildConfig.tfs.workspace -NoNewline -ForegroundColor DarkYellow;
    Write-Host " at " -NoNewline -ForegroundColor Cyan;
    Write-Host $buildConfig.tfs.location -NoNewline -ForegroundColor DarkYellow;
    Write-Host " ..." -ForegroundColor Cyan;
    
    Show-Process("deleting similar workspace","");
    Start-Process $buildConfig.tfs.tf `
        -ArgumentList "workspace","/delete","/noprompt",$buildConfig.tfs.workspace -NoNewWindow -Wait;
    
    if(Test-Path -Path $buildConfig.tfs.location)
    {
        Show-Process("deleting existing directory","");
        Remove-Item -Recurse -Force $buildConfig.tfs.location | Out-Null;
    }
    Show-Process("creating workspace local folder","");
    New-Item -ItemType directory -Path $buildConfig.tfs.location | Out-Null;
    Show-Process("successfully created workspace local folder ",$buildConfig.tfs.location);
    
    Show-Process("creating workspace","");
    Start-Process $buildConfig.tfs.tf -ArgumentList "workspace","/new","/noprompt", $buildConfig.tfs.workspace -NoNewWindow -Wait;
       
    Write-Host "workspace " -NoNewline -ForegroundColor Cyan;
    Write-Host $buildConfig.tfs.workspace -NoNewline -ForegroundColor DarkYellow;
    Write-Host " has been created at " -ForegroundColor Cyan -NoNewline; 
    Write-Host $buildConfig.tfs.location -NoNewline -ForegroundColor DarkYellow;
    Write-Host " ..." -ForegroundColor Cyan;
    ""
    $workspaceParam = -join("/workspace:",$buildConfig.tfs.workspace);
    Show-Process("mapping workspace to local folder","");
    Start-Process $buildConfig.tfs.tf -ArgumentList "workfold","/map",$completeProjectPath,$buildConfig.tfs.location,$workspaceParam -NoNewWindow -Wait ;
    Show-Process("succesfully mapped workspace to local folder","");
}
catch
{
    Write-Host "error creating workspace " -NoNewline -ForegroundColor White -BackgroundColor Red;
    Write-Host $buildConfig.tfs.workspace -ForegroundColor Yellow -BackgroundColor Red -NoNewline;
    Write-Host ", terminating process ..." -ForegroundColor White -BackgroundColor Red;
    exit; 
}
""
try
{
    Set-Location -Path $buildConfig.tfs.location;
    Write-Host "current active directory now at " -ForegroundColor Cyan -NoNewline;
    Write-Host (Get-Location).Path -ForegroundColor DarkYellow;

    Write-Host "pulling codes from tfs ...." -ForegroundColor Cyan;
    [array]$folders = $buildConfig.get.folders;

    if($folders.Length -lt 1)
    {
        #get all
        Write-Host "getting all files from the branch ..." -ForegroundColor Cyan;
        Start-Process $buildConfig.tfs.tf -ArgumentList "get",$completeProjectPath,"/recursive" -Wait;
    }
    else
    {
        #iterate and get
        for($k=0; $k -lt $folders.Length; $k++)
        {
            $folderToGet = -join($completeProjectPath,$folders[$k]);
            Write-Host "getting folder " -NoNewline -ForegroundColor Cyan;
            Write-Host $folders[$k] -NoNewline -ForegroundColor DarkYellow;
            Write-Host " ..." -ForegroundColor Cyan;
            Start-Process $buildConfig.tfs.tf -ArgumentList "get",$folderToGet,"/recursive" -Wait;
        }
    }

    Write-Host "successfully pulled the source code from tfs ..." -ForegroundColor Cyan;
    
}
catch
{
    Write-Host "error pulling codes from tfs, terminating process ..." -NoNewline -ForegroundColor White -BackgroundColor Red;
    exit; 
}
""
try
{
    Write-Host "building source code ..." -ForegroundColor Cyan;
    Write-Host "builder :" -ForegroundColor Yellow -NoNewline;
    Write-Host $buildConfig.build.builder -ForegroundColor DarkYellow;
    [array]$sequence = $buildConfig.build.sequence;
    for($i=0; $i -lt $sequence.Length; $i++)
    {
        $toBuild = -join($buildConfig.tfs.location,$sequence[$i]);
        Start-Process $buildConfig.build.builder -ArgumentList $toBuild, "/p:Configuration=Release" -Wait -RedirectStandardOutput buildout.txt -RedirectStandardError builderr.txt;
    }
}
catch
{
    Write-Host "error building the source code, terminating process ..." -NoNewline -ForegroundColor White -BackgroundColor Red;
    exit;
}
""
if($buildConfig.wrapAfterBuild.ToUpper().equals("YES"))
{   
    Write-Host "wrapping the needed artifacts to " -NoNewline -ForegroundColor Cyan;
    Write-Host $buildConfig.wrap.output_folder -NoNewline -ForegroundColor DarkYellow;
    Write-Host " ..." -ForegroundColor Cyan;   
    ""
    if(Test-Path -Path $buildConfig.wrap.output_folder)
    {
        Write-Host "deleting existing directory ..." -ForegroundColor Cyan;
        Remove-Item -Recurse -Force $buildConfig.wrap.output_folder | Out-Null;
    }
    Write-Host "successfully created " -NoNewline -ForegroundColor Cyan;
    Write-Host $buildConfig.wrap.output_folder -NoNewline -ForegroundColor DarkYellow;
    Write-Host " ..." -ForegroundColor Cyan; 

    [array]$outputs = $buildConfig.wrap.outputs;
    for($j=0; $j -lt $outputs.Length; $j++)
    {
        $outItem = $outputs[$j];
        $outputFolder = -join($buildConfig.wrap.output_folder,$outItem.location);
        
        Write-Host "creating output folder " -NoNewline -ForegroundColor Cyan;
        Write-Host $outputFolder -NoNewline -ForegroundColor DarkYellow;
        Write-Host " ..." -ForegroundColor Cyan;
        
        New-Item -ItemType directory -Path $outputFolder | Out-Null;
        Write-Host "successfully created output folder " -ForegroundColor Cyan -NoNewline;
        Write-Host $outputFolder -ForegroundColor DarkYellow -NoNewline;
        Write-Host " ..." -ForegroundColor Cyan;

        [array]$outputFiles = $outItem.files;
        for($l=0;$l -lt $outputFiles.Length; $l++)
        {
            try
            {
                $file = -join($buildConfig.tfs.location,$outputFiles[$l]);
                Write-Host "- copying file " -NoNewline -ForegroundColor Cyan;
                Write-Host $file -ForegroundColor DarkYellow -NoNewline;

                if(Test-Path -Path $file)
                {
                    Copy-Item -Path  $file -Destination $outputFolder
                }
                else
                {
                    Write-Host " : fail" -ForegroundColor Red;
                }

                Write-Host " : success" -ForegroundColor Green;
            }
            catch
            {
                Write-Host " : fail" -ForegroundColor Red;
            }
        }
    }

}


""
Write-Host "end." -ForegroundColor Cyan;

