$AllProtocols = [System.Net.SecurityProtocolType]::Tls -bor `
                [System.Net.SecurityProtocolType]::Tls11 -bor `
                [System.Net.SecurityProtocolType]::Tls12

[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

# Function 'DownloadComponents' downloads some components that need on build satge
#
# It gets two parameters list of maps and download path
#
# The map consists of: download_allways ($true/$false) - should this component should download every time
#                  name - name of the dowmloaded component
#                  link - component download link

function DownloadComponents {

  param ( $prereq_list, $path )

  [void](New-Item -ItemType Directory -Force -Path $path)
    
  ForEach ( $item in $prereq_list ) {
    $url = $item.link
    $output = $path + $item.name

    try
    {
      if( $item.download_allways ){
        [system.console]::WriteLine("Downloading $url")
        Invoke-WebRequest -Uri $url -OutFile $output
      } else {
        if(![System.IO.File]::Exists($output)){
          [system.console]::WriteLine("Downloading $url")
          Invoke-WebRequest -Uri $url -OutFile $output
        }
      }
    } catch {
      Write-Host "[ERROR] Can not download" $item.name "by link" $url
    }
  }
}

switch ( $env:DOCUMENT_SERVER_VERSION_EE )
{
  latest { $DOCUMENT_SERVER_EE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver-ee.exe" }
  custom { $DOCUMENT_SERVER_EE_LINK = $env:DOCUMENT_SERVER_EE_CUSTOM_LINK.Replace(",", "") }
}

switch ( $env:DOCUMENT_SERVER_VERSION_CE )
{
  latest { $DOCUMENT_SERVER_CE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver.exe" }
  custom { $DOCUMENT_SERVER_CE_LINK = $env:DOCUMENT_SERVER_CE_CUSTOM_LINK.Replace(",", "") }
}

switch ( $env:DOCUMENT_SERVER_VERSION_DE )
{
  latest { $DOCUMENT_SERVER_DE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver-de.exe" }
  custom { $DOCUMENT_SERVER_DE_LINK = $env:DOCUMENT_SERVER_DE_CUSTOM_LINK.Replace(",", "") }
}

$psql_version = '14.0'

$path_prereq = "${pwd}\buildtools\install\win\"

$opensearchstack_path = "${pwd}\buildtools\install\win\OpenSearchStack\"

$opensearch_version = '2.18.0'

$opensearchdashboards_version = '2.18.0'

$openresty_version = '1.27.1.1'

$fluentbit_version = '3.2.4'

$opensearchstack_components = @(

  @{
    download_allways = $false;
    name = "opensearch-dashboards-${opensearchdashboards_version}-windows-x64.zip";
    link = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${opensearchdashboards_version}/opensearch-dashboards-${opensearchdashboards_version}-windows-x64.zip";
  }

  @{
    download_allways = $false;
    name = "fluent-bit-${fluentbit_version}-win64.zip";
    link = "https://packages.fluentbit.io/windows/fluent-bit-${fluentbit_version}-win64.zip";
  }
)

$prerequisites = @(
  
  @{  
    download_allways = $false; 
    name = "nuget.exe"; 
    link = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe";
  }

  @{
    download_allways = $false;
    name = "opensearch-${opensearch_version}.zip";
    link = "https://artifacts.opensearch.org/releases/bundle/opensearch/${opensearch_version}/opensearch-${opensearch_version}-windows-x64.zip";
  }
  
  @{
    download_allways = $false;
    name = "openresty-${openresty_version}.zip";
    link = "https://openresty.org/download/openresty-${openresty_version}-win64.zip";
  }

  @{
    download_allways = $false;
    name = "ingest-attachment-${opensearch_version}.zip";
    link = "https://artifacts.opensearch.org/releases/plugins/ingest-attachment/${opensearch_version}/ingest-attachment-${opensearch_version}.zip";
  }

  @{  
    download_allways = $false; 
    name = "WinSW.NET4new.exe"; 
    link = "https://github.com/winsw/winsw/releases/download/v2.11.0/WinSW.NET4.exe";
  }

   @{  
    # Downloading onlyoffice-documentserver-ee for DocSpace Enterprise
    download_allways = $true; 
    name = "onlyoffice-documentserver-ee.exe"; 
    link = $DOCUMENT_SERVER_EE_LINK
  }

  @{
    # Downloading onlyoffice-documentserver for DocSpace Community
    download_allways = $true; 
    name = "onlyoffice-documentserver.exe"; 
    link = $DOCUMENT_SERVER_CE_LINK
  }
   
   @{  
    # Downloading onlyoffice-documentserver-de for DocSpace Developer
    download_allways = $true; 
    name = "onlyoffice-documentserver-de.exe"; 
    link = $DOCUMENT_SERVER_DE_LINK
  }
   
  @{  
    download_allways = $false; 
    name = "psqlodbc_15_x64.msi";
    link = "http://download.onlyoffice.com/install/windows/redist/psqlodbc_15_x64.msi"
  }

  @{  
    download_allways = $false; 
    name = "postgresql-${psql_version}-1-windows-x64.exe"; 
    link = "https://get.enterprisedb.com/postgresql/postgresql-${psql_version}-1-windows-x64.exe"
  }
)

$path_enterprise_prereq = "${pwd}\buildtools\install\win\redist\"

$enterprise_prerequisites = @(
  @{
    download_allways = $false;
    name = ".net_framework_4.8.exe";
    link = "https://download.visualstudio.microsoft.com/download/pr/014120d7-d689-4305-befd-3cb711108212/0fd66638cde16859462a6243a4629a50/ndp48-x86-x64-allos-enu.exe"
  }

  @{
    download_allways = $false;
    name = "aspnetcore-runtime-9.0.0-win-x64.exe";
    link = "https://download.visualstudio.microsoft.com/download/pr/815e6104-b92c-4cd5-8971-cba2f685002a/37befaa217f3269a152016da80a922c1/aspnetcore-runtime-9.0.0-win-x64.exe";
  }

  @{
    download_allways = $false;
    name = "dotnet-runtime-9.0.0-win-x64.exe";
    link = "https://download.visualstudio.microsoft.com/download/pr/99bd07c2-c95c-44dc-9d47-36d3b18df240/bdf26c62f69c1b783687c1dce83ccf7a/dotnet-runtime-9.0.0-win-x64.exe";
  }

  @{
    download_allways = $false;
    name = "vcredist_2013u5_x64.exe";
    link = "http://download.microsoft.com/download/C/C/2/CC2DF5F8-4454-44B4-802D-5EA68D086676/vcredist_x64.exe";
  }

   @{
    download_allways = $false;
    name = "VC_redist.x86.exe";
    link = "https://download.visualstudio.microsoft.com/download/pr/d60aa805-26e9-47df-b4e3-cd6fcc392333/A06AAC66734A618AB33C1522920654DDFC44FC13CAFAA0F0AB85B199C3D51DC0/VC_redist.x86.exe";
  }

  @{
    download_allways = $false;
    name = "VC_redist.x64.exe";
    link = "https://download.visualstudio.microsoft.com/download/pr/d60aa805-26e9-47df-b4e3-cd6fcc392333/7D7105C52FCD6766BEEE1AE162AA81E278686122C1E44890712326634D0B055E/VC_redist.x64.exe";
  }

  @{  
    download_allways = $false; 
    name = "mysql-connector-odbc-8.4.0-winx64.msi";
    link = "https://cdn.mysql.com/archives/mysql-connector-odbc-8.4/mysql-connector-odbc-8.4.0-winx64.msi";
  }

  @{  
    download_allways = $false; 
    name = "mysql-8.4.3-winx64.msi";
    link = "https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.3-winx64.msi";
  }

  @{  
    download_allways = $false; 
    name = "node-v20.11.1-x64.msi";
    link = "https://nodejs.org/dist/v20.11.1/node-v20.11.1-x64.msi";
  }

  @{  
    download_allways = $false; 
    name = "elasticsearch-7.16.3.msi";
    link = "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-7.16.3.msi";
  }

  @{  
    download_allways = $false; 
    name = "otp_win64_26.0.2.exe";
    link = "https://github.com/erlang/otp/releases/download/OTP-26.0.2/otp_win64_26.0.2.exe";
  }

  @{  
    download_allways = $false; 
    name = "rabbitmq-server-3.12.1.exe";
    link = "https://github.com/rabbitmq/rabbitmq-server/releases/download/v3.12.1/rabbitmq-server-3.12.1.exe";
  }

  @{  
    download_allways = $false; 
    name = "Redis-7.4.0-Windows-x64.msi"; 
    link = "https://github.com/ONLYOFFICE/redis-windows/releases/download/7.4.0/Redis-7.4.0-Windows-x64.msi";
  }

  @{  
    download_allways = $false; 
    name = "FFmpeg_Essentials.msi"; 
    link = "https://github.com/icedterminal/ffmpeg-installer/releases/download/6.0.0.20230306/FFmpeg_Essentials.msi";
  }

  @{  
    download_allways = $false; 
    name = "psqlodbc_15_x64.msi";
    link = "http://download.onlyoffice.com/install/windows/redist/psqlodbc_15_x64.msi"
  }

  @{  
    download_allways = $false; 
    name = "postgresql-${psql_version}-1-windows-x64.exe"; 
    link = "https://get.enterprisedb.com/postgresql/postgresql-${psql_version}-1-windows-x64.exe"
  }

  @{
    download_allways = $false;
    name = "certbot-2.6.0.exe";
    link = "https://github.com/certbot/certbot/releases/download/v2.6.0/certbot-beta-installer-win_amd64_signed.exe"
  }

  @{
    download_allways = $false;
    name = "jdk-21_windows-x64_bin.msi";
    link = "https://download.oracle.com/java/21/latest/jdk-21_windows-x64_bin.msi"
  }
  
  @{
    download_allways = $false;
    name = "FireDaemon-OpenSSL-x64-3.3.0.exe";
    link = "https://download.firedaemon.com/FireDaemon-OpenSSL/FireDaemon-OpenSSL-x64-3.3.0.exe"
  }
)

DownloadComponents $prerequisites $path_prereq

DownloadComponents $enterprise_prerequisites $path_enterprise_prereq

DownloadComponents $opensearchstack_components $opensearchstack_path