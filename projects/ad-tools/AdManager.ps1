#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive manager for Active Directory OUs and users.
.DESCRIPTION
    Windows 11-style, dependency-free WPF front end for the AD Tools project.
    All AD logic lives in lib/AdTools/AdTools.psm1; this file is only the shell.

    Actions accumulate in a queue. Nothing touches AD until the operator
    reviews the whole plan and presses Apply All. The queue stores the
    fully-resolved plan at add time, so what is reviewed is what executes.

    Design rules:
      - Windows PowerShell 5.1 only (scoped exception to the repo's PS7 rule).
      - STA apartment, PresentationFramework/PresentationCore/WindowsBase only.
        No third-party theme libraries; Fluent styling is hand-rolled XAML.
      - One entry at a time in the UI. No CSV bulk import.
      - Archive means Disable only. Groups are deferred this iteration.
      - The cleartext password is shown on screen on purpose and written only
        to the temporary credential record. It is never logged.
.NOTES
    Run with Windows PowerShell 5.1 on a host with the ActiveDirectory (RSAT)
    module, as a domain user. Lab only; never point at production.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RecordDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --- STA guard ---------------------------------------------------------------
# WPF requires a single-threaded apartment. If we were launched from an MTA host
# (some automation shells), relaunch ourselves in STA and exit this instance.
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne [System.Threading.ApartmentState]::STA) {
    $relaunch = New-Object System.Diagnostics.ProcessStartInfo
    $relaunch.FileName = 'powershell.exe'
    $relaunch.Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if ($RecordDirectory) {
        $relaunch.Arguments += " -RecordDirectory `"$RecordDirectory`""
    }
    $relaunch.UseShellExecute = $false
    [void][System.Diagnostics.Process]::Start($relaunch)
    return
}

# --- Assemblies and modules --------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'lib'
$modulePath = Join-Path -Path $modulePath -ChildPath 'AdTools'
$modulePath = Join-Path -Path $modulePath -ChildPath 'AdTools.psd1'
Import-Module -Name $modulePath -Force

try {
    Import-Module -Name ActiveDirectory -ErrorAction Stop
} catch {
    [void][System.Windows.MessageBox]::Show(
        "The ActiveDirectory module (RSAT) is not available.`n`nInstall it from an elevated prompt with:`n  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`n`nDetails: $($_.Exception.Message)",
        'AD Tools', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    return
}

# --- XAML --------------------------------------------------------------------
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="AD Tools"
    Height="800" Width="1280"
    MinHeight="660" MinWidth="1120"
    WindowStartupLocation="CenterScreen"
    Background="#F3F3F3"
    FontFamily="Segoe UI">
    <Window.Resources>
        <SolidColorBrush x:Key="AccentBrush" Color="#0067C0" />
        <SolidColorBrush x:Key="AccentHoverBrush" Color="#005A9E" />
        <SolidColorBrush x:Key="TextBrush" Color="#1B1B1B" />
        <SolidColorBrush x:Key="MutedBrush" Color="#616161" />
        <SolidColorBrush x:Key="CardBrush" Color="#FFFFFF" />
        <SolidColorBrush x:Key="CardBorderBrush" Color="#E3E3E3" />
        <SolidColorBrush x:Key="FieldBrush" Color="#FAFAFA" />

        <Style x:Key="Card" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}" />
            <Setter Property="BorderBrush" Value="{StaticResource CardBorderBrush}" />
            <Setter Property="BorderThickness" Value="1" />
            <Setter Property="CornerRadius" Value="8" />
            <Setter Property="Padding" Value="16" />
            <Setter Property="Margin" Value="0,0,0,12" />
        </Style>

        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="FontSize" Value="20" />
            <Setter Property="FontWeight" Value="SemiBold" />
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="Margin" Value="0,0,0,4" />
        </Style>

        <Style x:Key="FieldLabel" TargetType="TextBlock">
            <Setter Property="Margin" Value="0,10,0,4" />
            <Setter Property="Foreground" Value="{StaticResource MutedBrush}" />
            <Setter Property="FontSize" Value="13" />
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="White" />
            <Setter Property="Background" Value="{StaticResource AccentBrush}" />
            <Setter Property="Padding" Value="18,9" />
            <Setter Property="Margin" Value="0,0,8,0" />
            <Setter Property="FontSize" Value="14" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Border" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="{StaticResource AccentHoverBrush}" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Border" Property="Opacity" Value="0.4" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="Background" Value="#EDEDED" />
            <Setter Property="Padding" Value="18,9" />
            <Setter Property="Margin" Value="0,0,8,0" />
            <Setter Property="FontSize" Value="14" />
            <Setter Property="Cursor" Value="Hand" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="Border" Background="{TemplateBinding Background}" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#E0E0E0" />
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="Border" Property="Opacity" Value="0.4" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="NavItem" TargetType="ListBoxItem">
            <Setter Property="Padding" Value="14,11" />
            <Setter Property="Margin" Value="6,2" />
            <Setter Property="FontSize" Value="14" />
            <Setter Property="Foreground" Value="{StaticResource TextBrush}" />
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="Border" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}">
                            <ContentPresenter />
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#EDEDED" />
                            </Trigger>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter TargetName="Border" Property="Background" Value="#E1EEF9" />
                                <Setter Property="Foreground" Value="{StaticResource AccentBrush}" />
                                <Setter Property="FontWeight" Value="SemiBold" />
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto" />
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,0,0,1" Padding="20,14">
            <StackPanel>
                <TextBlock Text="AD Tools" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}" />
                <TextBlock x:Name="DomainLabel" Text="Domain: (loading...)" FontSize="13" Foreground="{StaticResource MutedBrush}" Margin="0,2,0,0" />
            </StackPanel>
        </Border>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="200" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="380" />
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,0,1,0">
                <ListBox x:Name="NavList" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource NavItem}" />
            </Border>

            <Grid Grid.Column="1">
                <ScrollViewer x:Name="PanelOu" VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Create organizational unit" />
                        <TextBlock Text="Creates a top-level OU and optionally seeds it with one agence per branch. Add departments to every new agence in the same action. Nothing is created until you press Apply All." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Parent container" />
                                <ComboBox x:Name="OuParentCombo" DisplayMemberPath="DisplayName" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="New OU name" />
                                <TextBox x:Name="OuNameBox" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence names (one per line, optional)" />
                                <TextBox x:Name="OuAgencesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Department names for each agence (one per line, optional)" />
                                <TextBox x:Name="OuDepartmentsBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="OuAddButton" Style="{StaticResource PrimaryButton}" Content="Add to queue" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Queued by this action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="OuPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" FontFamily="Consolas" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelAgence" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Add agence" />
                        <TextBlock Text="Adds one OU per agence under an existing or queued container. Nothing is created until you press Apply All." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Parent container" />
                                <ComboBox x:Name="AgParentCombo" DisplayMemberPath="DisplayName" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence names (one per line)" />
                                <TextBox x:Name="AgNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="88" VerticalScrollBarVisibility="Auto" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Department names for each agence (one per line, optional)" />
                                <TextBox x:Name="AgDepartmentsBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="AgAddButton" Style="{StaticResource PrimaryButton}" Content="Add to queue" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Queued by this action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="AgPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" FontFamily="Consolas" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelDepartment" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Add department" />
                        <TextBlock Text="Adds one OU per department under an agence. Users live in department OUs. Nothing is created until you press Apply All." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Parent agence" />
                                <ComboBox x:Name="DepParentCombo" DisplayMemberPath="DisplayName" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Department names (one per line)" />
                                <TextBox x:Name="DepNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="88" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="DepAddButton" Style="{StaticResource PrimaryButton}" Content="Add to queue" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Queued by this action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="DepPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" FontFamily="Consolas" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelUser" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Create user" />
                        <TextBlock Text="Queues one user in a department OU. The password is written to the credential record on success. Nothing is created until you press Apply All." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="16" />
                                        <ColumnDefinition Width="*" />
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Given name" />
                                        <TextBox x:Name="UserGivenBox" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Surname" />
                                        <TextBox x:Name="UserSurnameBox" />
                                    </StackPanel>
                                </Grid>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="User name (derived)" />
                                <TextBox x:Name="UserSamBox" IsReadOnly="True" Background="{StaticResource FieldBrush}" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Department OU" />
                                <ComboBox x:Name="UserOuCombo" DisplayMemberPath="DisplayName" />
                                <Grid Margin="0,14,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="16" />
                                        <ColumnDefinition Width="*" />
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <Button x:Name="UserGeneratePasswordButton" Style="{StaticResource SecondaryButton}" Content="Generate password" Margin="0" HorizontalAlignment="Left" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Password (shown in clear on purpose)" Margin="0,0,0,4" />
                                        <TextBox x:Name="UserPasswordBox" IsReadOnly="True" Background="{StaticResource FieldBrush}" FontFamily="Consolas" />
                                    </StackPanel>
                                </Grid>
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="UserAddButton" Style="{StaticResource PrimaryButton}" Content="Add to queue" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Queued by this action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="UserPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="110" Background="{StaticResource FieldBrush}" BorderThickness="0" FontFamily="Consolas" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelArchive" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Archive user" />
                        <TextBlock Text="Queues an account disable. The user is not deleted and not moved. Nothing happens until you press Apply All." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="User (SamAccountName)" />
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="8" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBox Grid.Column="0" x:Name="ArchiveUserBox" />
                                    <Button Grid.Column="2" x:Name="ArchiveLoadButton" Style="{StaticResource SecondaryButton}" Content="Load" Margin="0" />
                                </Grid>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Account" />
                                <TextBox x:Name="ArchiveInfoText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" Background="{StaticResource FieldBrush}" BorderThickness="0" MinHeight="70" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="ArchiveAddButton" Style="{StaticResource PrimaryButton}" Content="Add to queue" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Queued by this action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="ArchivePreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" FontFamily="Consolas" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </Grid>

            <Border Grid.Column="2" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="1,0,0,0">
                <Grid Margin="16">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="*" />
                        <RowDefinition Height="Auto" />
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0">
                        <TextBlock Text="Queue" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}" />
                        <TextBlock x:Name="QueueCountText" Text="Nothing queued." FontSize="13" Foreground="{StaticResource MutedBrush}" Margin="0,2,0,0" />
                    </StackPanel>

                    <ListBox Grid.Row="1" x:Name="QueueList" Margin="0,12,0,0" DisplayMemberPath="Label" FontFamily="Consolas" FontSize="12" />

                    <StackPanel Grid.Row="2" Margin="0,12,0,0">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="QueueApplyButton" Style="{StaticResource PrimaryButton}" Content="Apply all" IsEnabled="False" />
                            <Button x:Name="QueueRemoveButton" Style="{StaticResource SecondaryButton}" Content="Remove selected" IsEnabled="False" />
                        </StackPanel>
                        <Button x:Name="QueueClearButton" Style="{StaticResource SecondaryButton}" Content="Clear queue" HorizontalAlignment="Left" Margin="0,8,0,0" />
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,1,0,0" Padding="20,10">
            <TextBlock x:Name="StatusText" Text="Ready." FontSize="13" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" />
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# --- Element handles ---------------------------------------------------------
# Collect every named control once so the event handlers stay readable and we
# avoid repeating FindName calls throughout the wiring below.
$ui = @{}
foreach ($name in @(
        'DomainLabel', 'StatusText', 'NavList',
        'PanelOu', 'PanelAgence', 'PanelDepartment', 'PanelUser', 'PanelArchive',
        'OuParentCombo', 'OuNameBox', 'OuAgencesBox', 'OuDepartmentsBox',
        'OuAddButton', 'OuPreviewText',
        'AgParentCombo', 'AgNamesBox', 'AgDepartmentsBox', 'AgAddButton', 'AgPreviewText',
        'DepParentCombo', 'DepNamesBox', 'DepAddButton', 'DepPreviewText',
        'UserGivenBox', 'UserSurnameBox', 'UserSamBox', 'UserOuCombo',
        'UserGeneratePasswordButton', 'UserPasswordBox', 'UserAddButton', 'UserPreviewText',
        'ArchiveUserBox', 'ArchiveLoadButton', 'ArchiveInfoText', 'ArchiveAddButton', 'ArchivePreviewText',
        'QueueList', 'QueueCountText', 'QueueApplyButton', 'QueueRemoveButton', 'QueueClearButton'
    )) {
    $ui[$name] = $window.FindName($name)
}

# --- Script state ------------------------------------------------------------
# The queue holds fully-resolved plans. A queued OU can be selected as the
# parent of a later action, so a parent is always enqueued before its child and
# execution order is safe.
$script:queue = New-Object System.Collections.Generic.List[object]
$script:existingOus = @()
$script:generatedPassword = $null
$script:archiveUser = $null
$script:recordDirectory = $RecordDirectory

# --- UI helpers --------------------------------------------------------------
function Write-AdtStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter()]
        [ValidateSet('Info', 'Success', 'Error')]
        [string]$Kind = 'Info'
    )

    $ui['StatusText'].Text = $Text
    switch ($Kind) {
        'Success' {
            $ui['StatusText'].Foreground = [System.Windows.Media.Brushes]::DarkGreen
        }
        'Error' {
            $ui['StatusText'].Foreground = [System.Windows.Media.Brushes]::DarkRed
        }
        default {
            $ui['StatusText'].Foreground = [System.Windows.Media.Brushes]::DimGray
        }
    }
}

function Show-AdtMessage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter()]
        [string]$Title = 'AD Tools',

        [Parameter()]
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$Kind = 'Information'
    )

    $icon = [System.Windows.MessageBoxImage]::Information
    if ($Kind -eq 'Warning') {
        $icon = [System.Windows.MessageBoxImage]::Warning
    }
    if ($Kind -eq 'Error') {
        $icon = [System.Windows.MessageBoxImage]::Error
    }
    [void][System.Windows.MessageBox]::Show($Text, $Title, [System.Windows.MessageBoxButton]::OK, $icon)
}

function Confirm-AdtAction {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter()]
        [string]$Title = 'Confirm'
    )

    $result = [System.Windows.MessageBox]::Show(
        $Text, $Title, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    return [bool]($result -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-AdtMultilineItems {
    # Split a multi-line text box into a de-duplicated list of non-empty names.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Text
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($line in @($Text -split "`r?`n")) {
        $name = $line.Trim()
        if ($name -and ($items -notcontains $name)) {
            $items.Add($name)
        }
    }
    return [string[]]$items.ToArray()
}

function Get-AdtPendingOuPaths {
    # Distinguished names of OUs that are queued but not yet created.
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $script:queue) {
        if ($item.Kind -eq 'OU') {
            $paths.Add([string]$item.DistinguishedName)
        }
    }
    return [string[]]$paths.ToArray()
}

function Sync-AdtOuChoices {
    # Refresh the cached OUs and repopulate every parent picker. Queued OUs are
    # offered alongside real ones so a user can target an OU not created yet.
    [CmdletBinding()]
    param()

    try {
        $script:existingOus = @(Get-AdtOU)
    } catch {
        $script:existingOus = @()
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    }

    $choices = New-Object System.Collections.Generic.List[object]
    $root = [string](Get-AdtDefaultSearchBase)
    $choices.Add([pscustomobject]@{ DisplayName = $root; DistinguishedName = $root; Pending = $false })

    foreach ($ou in $script:existingOus) {
        $dn = [string]$ou.DistinguishedName
        if ($dn -ne $root) {
            $choices.Add([pscustomobject]@{ DisplayName = $dn; DistinguishedName = $dn; Pending = $false })
        }
    }
    foreach ($dn in Get-AdtPendingOuPaths) {
        if (-not ($choices | Where-Object { $_.DistinguishedName -eq $dn })) {
            $choices.Add([pscustomobject]@{ DisplayName = "$dn   (queued)"; DistinguishedName = $dn; Pending = $true })
        }
    }

    foreach ($combo in @($ui['OuParentCombo'], $ui['AgParentCombo'], $ui['DepParentCombo'], $ui['UserOuCombo'])) {
        $previous = $null
        if ($combo.SelectedItem) {
            $previous = [string]$combo.SelectedItem.DistinguishedName
        }
        $combo.ItemsSource = $choices
        $match = $choices | Where-Object { $_.DistinguishedName -eq $previous } | Select-Object -First 1
        if ($match) {
            $combo.SelectedItem = $match
        } elseif ($choices.Count -gt 0) {
            $combo.SelectedIndex = 0
        }
    }
}

function Sync-AdtSamPreview {
    [CmdletBinding()]
    param()

    try {
        $given = $ui['UserGivenBox'].Text.Trim()
        $surname = $ui['UserSurnameBox'].Text.Trim()
        if ($given -and $surname) {
            $ui['UserSamBox'].Text = Get-AdtSamAccountName -GivenName $given -Surname $surname
        } else {
            $ui['UserSamBox'].Text = ''
        }
    } catch {
        $ui['UserSamBox'].Text = ''
    }
}

function Sync-AdtPanelVisibility {
    [CmdletBinding()]
    param()

    $panels = @(
        $ui['PanelOu'], $ui['PanelAgence'], $ui['PanelDepartment'],
        $ui['PanelUser'], $ui['PanelArchive']
    )
    for ($i = 0; $i -lt $panels.Count; $i++) {
        if ($i -eq $ui['NavList'].SelectedIndex) {
            $panels[$i].Visibility = [System.Windows.Visibility]::Visible
        } else {
            $panels[$i].Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

function Sync-AdtQueue {
    # Rebind the queue list and keep the apply/remove buttons in step with it.
    [CmdletBinding()]
    param()

    $ui['QueueList'].ItemsSource = $null
    $ui['QueueList'].ItemsSource = $script:queue

    $count = $script:queue.Count
    if ($count -eq 0) {
        $ui['QueueCountText'].Text = 'Nothing queued.'
    } else {
        $ui['QueueCountText'].Text = "{0} action(s) pending." -f $count
    }
    $ui['QueueApplyButton'].IsEnabled = ($count -gt 0)
    $ui['QueueRemoveButton'].IsEnabled = ($count -gt 0)
}

function Add-AdtQueueItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item
    )

    $script:queue.Add($Item)
    Sync-AdtQueue
    Sync-AdtOuChoices
}

function Sync-AdtArchiveUser {
    [CmdletBinding()]
    param()

    try {
        $identity = $ui['ArchiveUserBox'].Text.Trim()
        if (-not $identity) {
            Show-AdtMessage -Text 'Enter a user (SamAccountName) to load.' -Kind 'Warning'
            return
        }

        $script:archiveUser = Get-AdtUser -Identity $identity
        $state = 'Enabled'
        if (-not $script:archiveUser.Enabled) {
            $state = 'Already disabled'
        }

        $lines = @(
            "SamAccountName : $($script:archiveUser.SamAccountName)"
            "Display name   : $($script:archiveUser.DisplayName)"
            "Distinguished  : $($script:archiveUser.DistinguishedName)"
            "Status         : $state"
        )
        $ui['ArchiveInfoText'].Text = ($lines -join [Environment]::NewLine)
        Write-AdtStatus -Text "Loaded $($script:archiveUser.SamAccountName)."
    } catch {
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
    }
}

# --- Queue builders ----------------------------------------------------------
function Add-AdtOuPlan {
    # Queue one OU plus, optionally, one child OU per agence and one grandchild
    # OU per department under each agence.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ParentPath,

        [Parameter()]
        [string[]]$Agences = @(),

        [Parameter()]
        [string[]]$Departments = @()
    )

    $queued = New-Object System.Collections.Generic.List[string]
    $parentDn = $ParentPath
    $topDn = "OU=$Name,$parentDn"
    Add-AdtQueueItem -Item ([pscustomobject]@{
            Kind = 'OU'
            Name = $Name
            ParentPath = $parentDn
            DistinguishedName = $topDn
            Label = "OU     $topDn"
        })
    $queued.Add($topDn)

    foreach ($agence in $Agences) {
        $agenceDn = "OU=$agence,$topDn"
        Add-AdtQueueItem -Item ([pscustomobject]@{
                Kind = 'OU'
                Name = $agence
                ParentPath = $topDn
                DistinguishedName = $agenceDn
                Label = "OU     $agenceDn"
            })
        $queued.Add($agenceDn)

        foreach ($department in $Departments) {
            $departmentDn = "OU=$department,$agenceDn"
            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'OU'
                    Name = $department
                    ParentPath = $agenceDn
                    DistinguishedName = $departmentDn
                    Label = "OU     $departmentDn"
                })
            $queued.Add($departmentDn)
        }
    }

    return [string[]]$queued.ToArray()
}

# --- Batch execution ---------------------------------------------------------
function Invoke-AdtQueue {
    # Execute the queue in dependency order: every OU first (in queue order, so
    # a parent is always created before its child), then users, then archives.
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $createdUsers = New-Object System.Collections.Generic.List[object]
    $failures = New-Object System.Collections.Generic.List[string]
    $done = 0

    foreach ($kind in @('OU', 'User', 'Archive')) {
        foreach ($item in @($script:queue | Where-Object { $_.Kind -eq $kind })) {
            try {
                switch ($kind) {
                    'OU' {
                        [void](New-AdtOU -Name $item.Name -ParentPath $item.ParentPath)
                    }
                    'User' {
                        $secure = ConvertTo-AdtSecureString -PlainText $item.Password
                        [void](New-AdtUser -SamAccountName $item.SamAccountName `
                                -GivenName $item.GivenName `
                                -Surname $item.Surname `
                                -Path $item.Path `
                                -AccountPassword $secure)
                        $createdUsers.Add([pscustomobject]@{
                                SamAccountName = $item.SamAccountName
                                Password = $item.Password
                            })
                    }
                    'Archive' {
                        [void](Disable-AdtUser -Identity $item.Identity)
                    }
                }
                $done++
            } catch {
                $failures.Add(("{0} : {1}" -f $item.Label, $_.Exception.Message))
            }
        }
    }

    $recordPath = $null
    if ($createdUsers.Count -gt 0) {
        if ($script:recordDirectory) {
            $saved = Save-AdtCredentialRecord -Record @($createdUsers) -Directory $script:recordDirectory
        } else {
            $saved = Save-AdtCredentialRecord -Record @($createdUsers)
        }
        $recordPath = [string]$saved.Path
    }

    return [pscustomobject]@{
        Succeeded = $done
        Failed = $failures.Count
        Failures = @($failures)
        UsersCreated = $createdUsers.Count
        RecordPath = $recordPath
    }
}

# --- Event wiring ------------------------------------------------------------

$ui['NavList'].Add_SelectionChanged({ Sync-AdtPanelVisibility })

# Create OU
$ui['OuAddButton'].Add_Click({
        try {
            $name = $ui['OuNameBox'].Text.Trim()
            $parent = $ui['OuParentCombo'].SelectedItem
            if (-not $name) {
                Show-AdtMessage -Text 'Enter a name for the new OU.' -Kind 'Warning'
                return
            }
            if (-not $parent) {
                Show-AdtMessage -Text 'Choose a parent container.' -Kind 'Warning'
                return
            }

            $agences = @(Get-AdtMultilineItems -Text $ui['OuAgencesBox'].Text)
            $departments = @(Get-AdtMultilineItems -Text $ui['OuDepartmentsBox'].Text)
            $parentDn = [string]$parent.DistinguishedName

            $queued = Add-AdtOuPlan -Name $name -ParentPath $parentDn -Agences $agences -Departments $departments
            $ui['OuPreviewText'].Text = ($queued -join [Environment]::NewLine)
            $ui['OuNameBox'].Text = ''
            $ui['OuAgencesBox'].Text = ''
            $ui['OuDepartmentsBox'].Text = ''
            Write-AdtStatus -Text ("Queued {0} OU(s). Review the queue, then press Apply all." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Add agence
$ui['AgAddButton'].Add_Click({
        try {
            $parent = $ui['AgParentCombo'].SelectedItem
            if (-not $parent) {
                Show-AdtMessage -Text 'Choose a parent container.' -Kind 'Warning'
                return
            }
            $agences = @(Get-AdtMultilineItems -Text $ui['AgNamesBox'].Text)
            if ($agences.Count -eq 0) {
                Show-AdtMessage -Text 'Enter at least one agence name.' -Kind 'Warning'
                return
            }
            $departments = @(Get-AdtMultilineItems -Text $ui['AgDepartmentsBox'].Text)

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($agence in $agences) {
                $queued.AddRange([string[]](Add-AdtOuPlan -Name $agence -ParentPath ([string]$parent.DistinguishedName) -Departments $departments))
            }
            $ui['AgPreviewText'].Text = ($queued -join [Environment]::NewLine)
            $ui['AgNamesBox'].Text = ''
            $ui['AgDepartmentsBox'].Text = ''
            Write-AdtStatus -Text ("Queued {0} OU(s). Review the queue, then press Apply all." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Add department
$ui['DepAddButton'].Add_Click({
        try {
            $parent = $ui['DepParentCombo'].SelectedItem
            if (-not $parent) {
                Show-AdtMessage -Text 'Choose a parent agence.' -Kind 'Warning'
                return
            }
            $departments = @(Get-AdtMultilineItems -Text $ui['DepNamesBox'].Text)
            if ($departments.Count -eq 0) {
                Show-AdtMessage -Text 'Enter at least one department name.' -Kind 'Warning'
                return
            }
            $parentDn = [string]$parent.DistinguishedName

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($department in $departments) {
                $dn = "OU=$department,$parentDn"
                Add-AdtQueueItem -Item ([pscustomobject]@{
                        Kind = 'OU'
                        Name = $department
                        ParentPath = $parentDn
                        DistinguishedName = $dn
                        Label = "OU     $dn"
                    })
                $queued.Add($dn)
            }
            $ui['DepPreviewText'].Text = ($queued -join [Environment]::NewLine)
            $ui['DepNamesBox'].Text = ''
            Write-AdtStatus -Text ("Queued {0} OU(s). Review the queue, then press Apply all." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Create user
$ui['UserGivenBox'].Add_TextChanged({ Sync-AdtSamPreview })
$ui['UserSurnameBox'].Add_TextChanged({ Sync-AdtSamPreview })

$ui['UserGeneratePasswordButton'].Add_Click({
        try {
            $generated = New-AdtPassword
            $script:generatedPassword = [string]$generated.Password
            $ui['UserPasswordBox'].Text = $script:generatedPassword
            Write-AdtStatus -Text 'Password generated.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['UserAddButton'].Add_Click({
        try {
            $given = $ui['UserGivenBox'].Text.Trim()
            $surname = $ui['UserSurnameBox'].Text.Trim()
            $ou = $ui['UserOuCombo'].SelectedItem
            if (-not $given -or -not $surname) {
                Show-AdtMessage -Text 'Enter a given name and a surname.' -Kind 'Warning'
                return
            }
            if (-not $ou) {
                Show-AdtMessage -Text 'Choose a department OU.' -Kind 'Warning'
                return
            }

            if (-not $script:generatedPassword) {
                $generated = New-AdtPassword
                $script:generatedPassword = [string]$generated.Password
                $ui['UserPasswordBox'].Text = $script:generatedPassword
            }

            $sam = Get-AdtSamAccountName -GivenName $given -Surname $surname
            $path = [string]$ou.DistinguishedName
            $label = "USER   $sam   pw=$script:generatedPassword   ->  $path"

            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'User'
                    GivenName = $given
                    Surname = $surname
                    SamAccountName = $sam
                    Path = $path
                    Password = $script:generatedPassword
                    Label = $label
                })

            $ui['UserPreviewText'].Text = (
                "Queued user:" +
                [Environment]::NewLine + "  Display name : $given $surname" +
                [Environment]::NewLine + "  SamAccount   : $sam" +
                [Environment]::NewLine + "  OU           : $path" +
                [Environment]::NewLine + "  Password     : $script:generatedPassword" +
                [Environment]::NewLine + "  Change password at next logon : no"
            )

            $script:generatedPassword = $null
            $ui['UserPasswordBox'].Text = ''
            $ui['UserGivenBox'].Text = ''
            $ui['UserSurnameBox'].Text = ''
            $ui['UserSamBox'].Text = ''
            Write-AdtStatus -Text "Queued $sam. Review the queue, then press Apply all." -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Archive user
$ui['ArchiveLoadButton'].Add_Click({ Sync-AdtArchiveUser })

$ui['ArchiveAddButton'].Add_Click({
        try {
            if (-not $script:archiveUser) {
                Show-AdtMessage -Text 'Load a user first.' -Kind 'Warning'
                return
            }
            $sam = [string]$script:archiveUser.SamAccountName
            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'Archive'
                    Identity = $sam
                    Label = "ARCH  $sam"
                })
            $ui['ArchivePreviewText'].Text = "Queued disable for '$sam'."
            $ui['ArchiveUserBox'].Text = ''
            $ui['ArchiveInfoText'].Text = ''
            $script:archiveUser = $null
            Write-AdtStatus -Text "Queued disable for $sam. Review the queue, then press Apply all." -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Queue controls
$ui['QueueRemoveButton'].Add_Click({
        try {
            $selected = @($ui['QueueList'].SelectedItems)
            if ($selected.Count -eq 0) {
                return
            }
            foreach ($item in $selected) {
                [void]$script:queue.Remove($item)
            }
            Sync-AdtQueue
            Sync-AdtOuChoices
            Write-AdtStatus -Text ("Removed {0} queued action(s)." -f $selected.Count)
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['QueueClearButton'].Add_Click({
        $script:queue.Clear()
        Sync-AdtQueue
        Sync-AdtOuChoices
        Write-AdtStatus -Text 'Queue cleared.'
    })

$ui['QueueApplyButton'].Add_Click({
        try {
            if ($script:queue.Count -eq 0) {
                return
            }

            $summary = @()
            foreach ($item in $script:queue) {
                $summary += "  $($item.Label)"
            }
            $body = "Apply these {0} action(s) to the directory?`n`n{1}" -f $script:queue.Count, ($summary -join [Environment]::NewLine)
            if (-not (Confirm-AdtAction -Text $body -Title 'Apply all')) {
                return
            }

            $result = Invoke-AdtQueue
            $script:queue.Clear()
            Sync-AdtQueue
            Sync-AdtOuChoices

            $lines = @(
                "Succeeded : $($result.Succeeded)"
                "Failed    : $($result.Failed)"
            )
            if ($result.UsersCreated -gt 0) {
                $lines += ''
                $lines += "Credential record: $($result.RecordPath)"
                $lines += 'That file is cleartext. Hand it over, then delete it.'
                $lines += 'Never commit it and never leave it in the repository.'
            }
            if ($result.Failed -gt 0) {
                $lines += ''
                $lines += 'Failures:'
                foreach ($failure in $result.Failures) {
                    $lines += "  $failure"
                }
            }

            $icon = [System.Windows.MessageBoxImage]::Information
            if ($result.Failed -gt 0) {
                $icon = [System.Windows.MessageBoxImage]::Warning
            }
            [void][System.Windows.MessageBox]::Show(
                ($lines -join [Environment]::NewLine), 'Apply all',
                [System.Windows.MessageBoxButton]::OK, $icon)

            if ($result.Failed -gt 0) {
                Write-AdtStatus -Text ("Applied {0} action(s); {1} failed." -f $result.Succeeded, $result.Failed) -Kind 'Error'
            } else {
                Write-AdtStatus -Text ("Applied {0} action(s)." -f $result.Succeeded) -Kind 'Success'
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# --- Initial population ------------------------------------------------------
$ui['NavList'].ItemsSource = @('Create OU', 'Add agence', 'Add department', 'Create user', 'Archive user')
$ui['NavList'].SelectedIndex = 0

try {
    $domain = Get-AdtDefaultSearchBase
    $ui['DomainLabel'].Text = "Domain: $domain"
} catch {
    $ui['DomainLabel'].Text = 'Domain: unavailable'
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    Show-AdtMessage -Text ("Could not read the Active Directory domain.`n`n{0}" -f $_.Exception.Message) -Kind 'Error'
}

try {
    Sync-AdtOuChoices
    Sync-AdtQueue
    Write-AdtStatus -Text 'Ready.'
} catch {
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
}

# --- Run ---------------------------------------------------------------------
[void]$window.ShowDialog()
