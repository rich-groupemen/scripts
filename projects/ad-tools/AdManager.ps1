#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive manager for Active Directory OUs, users, and groups.
.DESCRIPTION
    Windows 11-style, dependency-free WPF front end for the AD Tools project.
    All AD logic lives in lib/AdTools/AdTools.psm1; this file is only the shell:
    it collects input, shows a faithful preview (including the cleartext
    password), asks for explicit confirmation, then calls the module.

    Design rules:
      - Windows PowerShell 5.1 only (scoped exception to the repo's PS7 rule).
      - STA apartment, PresentationFramework/PresentationCore/WindowsBase only.
        No third-party theme libraries; Fluent styling is hand-rolled XAML.
      - One entry at a time. No CSV bulk import.
      - Nothing changes until the operator previews and confirms.
      - Archive means Disable only. Modify means group membership only.
      - The cleartext password is shown on screen on purpose and written only
        to the temporary credential record. It is never logged.
.NOTES
    Run with Windows PowerShell 5.1 on a host with the ActiveDirectory (RSAT)
    module. Lab only; never point at production.
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
    Height="740" Width="1100"
    MinHeight="620" MinWidth="940"
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
                <ColumnDefinition Width="220" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,0,1,0">
                <ListBox x:Name="NavList" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource NavItem}" />
            </Border>

            <Grid Grid.Column="1">
                <ScrollViewer x:Name="PanelOu" VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Create organizational unit" />
                        <TextBlock Text="Adds a new OU under an existing container. Nothing changes until you confirm." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Parent container" />
                                <ComboBox x:Name="OuParentCombo" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="New OU name" />
                                <TextBox x:Name="OuNameBox" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="OuPreviewButton" Style="{StaticResource SecondaryButton}" Content="Preview" />
                                    <Button x:Name="OuCreateButton" Style="{StaticResource PrimaryButton}" Content="Create OU" IsEnabled="False" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Preview" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="OuPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelUser" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Create user" />
                        <TextBlock Text="Creates one user and writes a temporary cleartext credential record on success." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
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
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Organizational unit" />
                                <ComboBox x:Name="UserOuCombo" />
                                <Grid Margin="0,10,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Style="{StaticResource FieldLabel}" Text="Groups (multi-select)" Margin="0,0,8,0" VerticalAlignment="Bottom" />
                                    <Button Grid.Column="1" x:Name="UserRefreshGroupsButton" Style="{StaticResource SecondaryButton}" Content="Refresh groups" Margin="0" Padding="12,6" />
                                </Grid>
                                <ListBox x:Name="UserGroupList" Height="140" SelectionMode="Multiple" DisplayMemberPath="Name" />
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
                                    <Button x:Name="UserPreviewButton" Style="{StaticResource SecondaryButton}" Content="Preview" />
                                    <Button x:Name="UserCreateButton" Style="{StaticResource PrimaryButton}" Content="Create user" IsEnabled="False" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Preview" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="UserPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="130" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelGroup" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Create group" />
                        <TextBlock Text="Creates a group with no permissions configured." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Organizational unit" />
                                <ComboBox x:Name="GroupOuCombo" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Group name" />
                                <TextBox x:Name="GroupNameBox" />
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="16" />
                                        <ColumnDefinition Width="*" />
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Scope" />
                                        <ComboBox x:Name="GroupScopeCombo" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Category" />
                                        <ComboBox x:Name="GroupCategoryCombo" />
                                    </StackPanel>
                                </Grid>
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="GroupPreviewButton" Style="{StaticResource SecondaryButton}" Content="Preview" />
                                    <Button x:Name="GroupCreateButton" Style="{StaticResource PrimaryButton}" Content="Create group" IsEnabled="False" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Preview" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="GroupPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelModify" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Modify user" />
                        <TextBlock Text="Changes group membership only. No other attributes are touched." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="User (SamAccountName)" />
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="8" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBox Grid.Column="0" x:Name="ModifyUserBox" />
                                    <Button Grid.Column="2" x:Name="ModifyLoadButton" Style="{StaticResource SecondaryButton}" Content="Load" Margin="0" />
                                </Grid>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Current groups" />
                                <ListBox x:Name="ModifyCurrentList" Height="90" DisplayMemberPath="Name" />
                                <Grid Margin="0,10,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Style="{StaticResource FieldLabel}" Text="Groups in the user's OU" VerticalAlignment="Bottom" Margin="0,0,8,0" />
                                    <Button Grid.Column="1" x:Name="ModifyRefreshButton" Style="{StaticResource SecondaryButton}" Content="Refresh" Margin="0" Padding="12,6" />
                                </Grid>
                                <ListBox x:Name="ModifyAvailableList" Height="120" SelectionMode="Multiple" DisplayMemberPath="Name" />
                                <StackPanel Orientation="Horizontal" Margin="0,14,0,0">
                                    <Button x:Name="ModifyAddButton" Style="{StaticResource SecondaryButton}" Content="Add selected" />
                                    <Button x:Name="ModifyRemoveButton" Style="{StaticResource SecondaryButton}" Content="Remove selected" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Pending changes" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="ModifyPendingText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="70" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                                <Button x:Name="ModifyApplyButton" Style="{StaticResource PrimaryButton}" Content="Apply changes" Margin="0,14,0,0" HorizontalAlignment="Left" IsEnabled="False" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelArchive" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Archive user" />
                        <TextBlock Text="Disables the account. The user is not deleted and not moved." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
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
                                    <Button x:Name="ArchivePreviewButton" Style="{StaticResource SecondaryButton}" Content="Preview" />
                                    <Button x:Name="ArchiveButton" Style="{StaticResource PrimaryButton}" Content="Disable account" IsEnabled="False" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Preview" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="ArchivePreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>
            </Grid>
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
        'PanelOu', 'PanelUser', 'PanelGroup', 'PanelModify', 'PanelArchive',
        'OuParentCombo', 'OuNameBox', 'OuPreviewButton', 'OuCreateButton', 'OuPreviewText',
        'UserGivenBox', 'UserSurnameBox', 'UserSamBox', 'UserOuCombo',
        'UserRefreshGroupsButton', 'UserGroupList', 'UserGeneratePasswordButton',
        'UserPasswordBox', 'UserPreviewButton', 'UserCreateButton', 'UserPreviewText',
        'GroupOuCombo', 'GroupNameBox', 'GroupScopeCombo', 'GroupCategoryCombo',
        'GroupPreviewButton', 'GroupCreateButton', 'GroupPreviewText',
        'ModifyUserBox', 'ModifyLoadButton', 'ModifyCurrentList', 'ModifyRefreshButton',
        'ModifyAvailableList', 'ModifyAddButton', 'ModifyRemoveButton',
        'ModifyPendingText', 'ModifyApplyButton',
        'ArchiveUserBox', 'ArchiveLoadButton', 'ArchiveInfoText',
        'ArchivePreviewButton', 'ArchiveButton', 'ArchivePreviewText'
    )) {
    $ui[$name] = $window.FindName($name)
}

# --- Script state ------------------------------------------------------------
# Planned changes are computed at preview time and reused at execution time, so
# the preview and the executed action can never diverge.
$script:generatedPassword = $null
$script:plannedOu = $null
$script:plannedUser = $null
$script:plannedGroup = $null
$script:modifyUser = $null
$script:modifyPending = @{}
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

function Get-AdtOuChoices {
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    $choices = New-Object System.Collections.Generic.List[string]
    $choices.Add([string](Get-AdtDefaultSearchBase))
    foreach ($ou in @(Get-AdtOU)) {
        $choices.Add([string]$ou.DistinguishedName)
    }
    return [string[]]$choices.ToArray()
}

function Sync-AdtOuCombos {
    [CmdletBinding()]
    param()

    $choices = Get-AdtOuChoices
    foreach ($combo in @($ui['OuParentCombo'], $ui['UserOuCombo'], $ui['GroupOuCombo'])) {
        $previous = $combo.SelectedItem
        $combo.ItemsSource = $choices
        if ($previous -and ($choices -contains $previous)) {
            $combo.SelectedItem = $previous
        } elseif ($choices.Count -gt 0) {
            $combo.SelectedIndex = 0
        }
    }
}

function Sync-AdtUserGroupList {
    [CmdletBinding()]
    param()

    $ou = $ui['UserOuCombo'].SelectedItem
    if (-not $ou) {
        $ui['UserGroupList'].ItemsSource = @()
        return
    }

    try {
        $groups = @(Get-AdtGroup -SearchBase $ou)
        $ui['UserGroupList'].ItemsSource = $groups
        Write-AdtStatus -Text ("Loaded {0} group(s) from {1}." -f $groups.Count, $ou)
    } catch {
        $ui['UserGroupList'].ItemsSource = @()
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
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
        $ui['PanelOu'], $ui['PanelUser'], $ui['PanelGroup'],
        $ui['PanelModify'], $ui['PanelArchive']
    )
    for ($i = 0; $i -lt $panels.Count; $i++) {
        if ($i -eq $ui['NavList'].SelectedIndex) {
            $panels[$i].Visibility = [System.Windows.Visibility]::Visible
        } else {
            $panels[$i].Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

function Sync-AdtModifyPending {
    [CmdletBinding()]
    param()

    if ($script:modifyPending.Count -eq 0) {
        $ui['ModifyPendingText'].Text = 'No pending changes.'
        $ui['ModifyApplyButton'].IsEnabled = $false
        return
    }

    $lines = @()
    foreach ($key in $script:modifyPending.Keys) {
        $lines += ("  {0,-6} {1}" -f $script:modifyPending[$key], $key)
    }
    $ui['ModifyPendingText'].Text = ($lines -join [Environment]::NewLine)
    $ui['ModifyApplyButton'].IsEnabled = $true
}

function Sync-AdtModifyUser {
    [CmdletBinding()]
    param()

    try {
        $identity = $ui['ModifyUserBox'].Text.Trim()
        if (-not $identity) {
            Show-AdtMessage -Text 'Enter a user (SamAccountName) to load.' -Kind 'Warning'
            return
        }

        $script:modifyUser = Get-AdtUser -Identity $identity
        $memberships = @($script:modifyUser.MemberOf | ForEach-Object { [pscustomobject]@{ Name = [string]$_ } })
        $ui['ModifyCurrentList'].ItemsSource = $memberships

        $dn = [string]$script:modifyUser.DistinguishedName
        $index = $dn.IndexOf(',')
        if ($index -ge 0) {
            $searchBase = $dn.Substring($index + 1)
        } else {
            $searchBase = Get-AdtDefaultSearchBase
        }
        $ui['ModifyAvailableList'].ItemsSource = @(Get-AdtGroup -SearchBase $searchBase)

        $script:modifyPending = @{}
        Sync-AdtModifyPending
        Write-AdtStatus -Text "Loaded $($script:modifyUser.SamAccountName) ($($memberships.Count) group(s))."
    } catch {
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
    }
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
        $ui['ArchivePreviewText'].Text = ''
        $ui['ArchiveButton'].IsEnabled = $false
        Write-AdtStatus -Text "Loaded $($script:archiveUser.SamAccountName)."
    } catch {
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
    }
}

# --- Event wiring ------------------------------------------------------------

$ui['NavList'].Add_SelectionChanged({ Sync-AdtPanelVisibility })

# Create OU
$ui['OuPreviewButton'].Add_Click({
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

            $script:plannedOu = [pscustomobject]@{ Name = $name; Parent = [string]$parent }
            $lines = @(
                'Will create organizational unit:'
                "  Name   : $name"
                "  Parent : $parent"
                ''
                'No change is made until you press Create OU.'
            )
            $ui['OuPreviewText'].Text = ($lines -join [Environment]::NewLine)
            $ui['OuCreateButton'].IsEnabled = $true
            Write-AdtStatus -Text 'OU preview ready. Press Create OU to apply.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['OuCreateButton'].Add_Click({
        try {
            if (-not $script:plannedOu) {
                return
            }
            $prompt = "Create OU '{0}' under '{1}'?" -f $script:plannedOu.Name, $script:plannedOu.Parent
            if (-not (Confirm-AdtAction -Text $prompt -Title 'Create organizational unit')) {
                return
            }

            $result = New-AdtOU -Name $script:plannedOu.Name -ParentPath $script:plannedOu.Parent
            if ($result.Success) {
                Write-AdtStatus -Text "Created OU $($result.DistinguishedName)." -Kind 'Success'
                $ui['OuPreviewText'].Text = "Created:`r`n  $($result.DistinguishedName)"
                $ui['OuCreateButton'].IsEnabled = $false
                $ui['OuNameBox'].Text = ''
                Sync-AdtOuCombos
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Create user
$ui['UserGivenBox'].Add_TextChanged({ Sync-AdtSamPreview })
$ui['UserSurnameBox'].Add_TextChanged({ Sync-AdtSamPreview })
$ui['UserOuCombo'].Add_SelectionChanged({ Sync-AdtUserGroupList })
$ui['UserRefreshGroupsButton'].Add_Click({ Sync-AdtUserGroupList })

$ui['UserGeneratePasswordButton'].Add_Click({
        try {
            $generated = New-AdtPassword
            $script:generatedPassword = [string]$generated.Password
            $ui['UserPasswordBox'].Text = $script:generatedPassword
            $ui['UserCreateButton'].IsEnabled = $false
            Write-AdtStatus -Text 'Password generated. Preview the user to enable creation.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['UserPreviewButton'].Add_Click({
        try {
            $given = $ui['UserGivenBox'].Text.Trim()
            $surname = $ui['UserSurnameBox'].Text.Trim()
            $ou = $ui['UserOuCombo'].SelectedItem
            if (-not $given -or -not $surname) {
                Show-AdtMessage -Text 'Enter a given name and a surname.' -Kind 'Warning'
                return
            }
            if (-not $ou) {
                Show-AdtMessage -Text 'Choose an organizational unit.' -Kind 'Warning'
                return
            }
            if (-not $script:generatedPassword) {
                Show-AdtMessage -Text 'Generate a password first.' -Kind 'Warning'
                return
            }

            $sam = Get-AdtSamAccountName -GivenName $given -Surname $surname
            $groupDns = @($ui['UserGroupList'].SelectedItems | ForEach-Object { [string]$_.DistinguishedName })
            $script:plannedUser = [pscustomobject]@{
                GivenName = $given
                Surname = $surname
                Sam = $sam
                Ou = [string]$ou
                Groups = $groupDns
            }

            $groupsText = '(none)'
            if ($groupDns.Count -gt 0) {
                $groupsText = $groupDns -join ([Environment]::NewLine + '             ')
            }
            $lines = @(
                'Will create user:'
                "  Display name : $given $surname"
                "  SamAccount   : $sam"
                "  OU           : $ou"
                "  Groups       : $groupsText"
                "  Password     : $script:generatedPassword"
                '  Change password at next logon : no'
                ''
                'The password above is shown in clear on purpose and will be'
                'written to the temporary credential record on success.'
            )
            $ui['UserPreviewText'].Text = ($lines -join [Environment]::NewLine)
            $ui['UserCreateButton'].IsEnabled = $true
            Write-AdtStatus -Text 'User preview ready. Press Create user to apply.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['UserCreateButton'].Add_Click({
        try {
            if (-not $script:plannedUser) {
                return
            }
            $prompt = "Create user '{0}' in '{1}'?" -f $script:plannedUser.Sam, $script:plannedUser.Ou
            if (-not (Confirm-AdtAction -Text $prompt -Title 'Create user')) {
                return
            }

            $secure = ConvertTo-AdtSecureString -PlainText $script:generatedPassword
            $result = New-AdtUser -SamAccountName $script:plannedUser.Sam `
                -GivenName $script:plannedUser.GivenName `
                -Surname $script:plannedUser.Surname `
                -Path $script:plannedUser.Ou `
                -AccountPassword $secure `
                -Group $script:plannedUser.Groups

            $record = [pscustomobject]@{
                SamAccountName = $result.SamAccountName
                Password = $script:generatedPassword
            }
            if ($script:recordDirectory) {
                $saved = Save-AdtCredentialRecord -Record @($record) -Directory $script:recordDirectory
            } else {
                $saved = Save-AdtCredentialRecord -Record @($record)
            }

            $lines = @(
                "Created $($result.SamAccountName)."
                ''
                "Credential record: $($saved.Path)"
                ''
                'That file is cleartext. Give it to the user, then delete it.'
                'Never commit it and never leave it in the repository.'
            )
            $ui['UserPreviewText'].Text = ($lines -join [Environment]::NewLine)
            $ui['UserCreateButton'].IsEnabled = $false
            $script:plannedUser = $null
            $script:generatedPassword = $null
            $ui['UserPasswordBox'].Text = ''
            $ui['UserGivenBox'].Text = ''
            $ui['UserSurnameBox'].Text = ''
            $ui['UserSamBox'].Text = ''
            $ui['UserGroupList'].SelectedItems.Clear()
            Write-AdtStatus -Text "Created $($result.SamAccountName). Credentials written to $($saved.Path)." -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Create group
$ui['GroupPreviewButton'].Add_Click({
        try {
            $name = $ui['GroupNameBox'].Text.Trim()
            $ou = $ui['GroupOuCombo'].SelectedItem
            if (-not $name) {
                Show-AdtMessage -Text 'Enter a group name.' -Kind 'Warning'
                return
            }
            if (-not $ou) {
                Show-AdtMessage -Text 'Choose an organizational unit.' -Kind 'Warning'
                return
            }

            $scope = [string]$ui['GroupScopeCombo'].SelectedItem
            $category = [string]$ui['GroupCategoryCombo'].SelectedItem
            $script:plannedGroup = [pscustomobject]@{ Name = $name; Ou = [string]$ou; Scope = $scope; Category = $category }

            $lines = @(
                'Will create group:'
                "  Name     : $name"
                "  OU       : $ou"
                "  Scope    : $scope"
                "  Category : $category"
                ''
                'No permissions are configured.'
            )
            $ui['GroupPreviewText'].Text = ($lines -join [Environment]::NewLine)
            $ui['GroupCreateButton'].IsEnabled = $true
            Write-AdtStatus -Text 'Group preview ready. Press Create group to apply.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['GroupCreateButton'].Add_Click({
        try {
            if (-not $script:plannedGroup) {
                return
            }
            $prompt = "Create group '{0}' in '{1}'?" -f $script:plannedGroup.Name, $script:plannedGroup.Ou
            if (-not (Confirm-AdtAction -Text $prompt -Title 'Create group')) {
                return
            }

            $result = New-AdtGroup -Name $script:plannedGroup.Name -Path $script:plannedGroup.Ou `
                -GroupScope $script:plannedGroup.Scope -GroupCategory $script:plannedGroup.Category
            if ($result.Success) {
                Write-AdtStatus -Text "Created group $($result.DistinguishedName)." -Kind 'Success'
                $ui['GroupPreviewText'].Text = "Created:`r`n  $($result.DistinguishedName)"
                $ui['GroupCreateButton'].IsEnabled = $false
                $ui['GroupNameBox'].Text = ''
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Modify user (group membership only)
$ui['ModifyLoadButton'].Add_Click({ Sync-AdtModifyUser })
$ui['ModifyRefreshButton'].Add_Click({ Sync-AdtModifyUser })

$ui['ModifyAddButton'].Add_Click({
        try {
            if (-not $script:modifyUser) {
                Show-AdtMessage -Text 'Load a user first.' -Kind 'Warning'
                return
            }
            $selected = @($ui['ModifyAvailableList'].SelectedItems)
            if ($selected.Count -eq 0) {
                Show-AdtMessage -Text 'Select one or more groups.' -Kind 'Warning'
                return
            }

            foreach ($group in $selected) {
                $dn = [string]$group.DistinguishedName
                if (@($script:modifyUser.MemberOf) -contains $dn) {
                    $script:modifyPending.Remove($dn) | Out-Null
                } else {
                    $script:modifyPending[$dn] = 'Add'
                }
            }
            Sync-AdtModifyPending
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['ModifyRemoveButton'].Add_Click({
        try {
            if (-not $script:modifyUser) {
                Show-AdtMessage -Text 'Load a user first.' -Kind 'Warning'
                return
            }
            $selected = @($ui['ModifyAvailableList'].SelectedItems)
            if ($selected.Count -eq 0) {
                Show-AdtMessage -Text 'Select one or more groups.' -Kind 'Warning'
                return
            }

            foreach ($group in $selected) {
                $dn = [string]$group.DistinguishedName
                if (@($script:modifyUser.MemberOf) -contains $dn) {
                    $script:modifyPending[$dn] = 'Remove'
                } else {
                    $script:modifyPending.Remove($dn) | Out-Null
                }
            }
            Sync-AdtModifyPending
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['ModifyApplyButton'].Add_Click({
        try {
            if (-not $script:modifyUser) {
                return
            }
            if ($script:modifyPending.Count -eq 0) {
                return
            }

            $summary = @()
            foreach ($dn in $script:modifyPending.Keys) {
                $summary += ("  {0} {1}" -f $script:modifyPending[$dn], $dn)
            }
            $prompt = "Apply these membership changes to '{0}'?`n`n{1}" -f $script:modifyUser.SamAccountName, ($summary -join [Environment]::NewLine)
            if (-not (Confirm-AdtAction -Text $prompt -Title 'Modify user')) {
                return
            }

            $applied = 0
            foreach ($dn in @($script:modifyPending.Keys)) {
                $action = $script:modifyPending[$dn]
                if ($action -eq 'Add') {
                    [void](Add-AdtGroupMember -Identity $dn -Members $script:modifyUser.SamAccountName)
                } else {
                    [void](Remove-AdtGroupMember -Identity $dn -Members $script:modifyUser.SamAccountName)
                }
                $applied++
            }

            Write-AdtStatus -Text "Applied $applied membership change(s) to $($script:modifyUser.SamAccountName)." -Kind 'Success'
            $script:modifyPending = @{}
            Sync-AdtModifyUser
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Archive user (disable only)
$ui['ArchiveLoadButton'].Add_Click({ Sync-AdtArchiveUser })

$ui['ArchivePreviewButton'].Add_Click({
        try {
            if (-not $script:archiveUser) {
                Show-AdtMessage -Text 'Load a user first.' -Kind 'Warning'
                return
            }
            $lines = @(
                "Will disable account '$($script:archiveUser.SamAccountName)'."
                ''
                'The account is not deleted and is not moved. Group membership and'
                'all other attributes are left unchanged.'
            )
            $ui['ArchivePreviewText'].Text = ($lines -join [Environment]::NewLine)
            $ui['ArchiveButton'].IsEnabled = $true
            Write-AdtStatus -Text 'Archive preview ready. Press Disable account to apply.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['ArchiveButton'].Add_Click({
        try {
            if (-not $script:archiveUser) {
                return
            }
            $prompt = "Disable account '{0}'?" -f $script:archiveUser.SamAccountName
            if (-not (Confirm-AdtAction -Text $prompt -Title 'Archive user')) {
                return
            }

            $result = Disable-AdtUser -Identity $script:archiveUser.SamAccountName
            if ($result.Success) {
                $ui['ArchivePreviewText'].Text = "Disabled $($result.Identity)."
                $ui['ArchiveButton'].IsEnabled = $false
                Write-AdtStatus -Text "Disabled $($result.Identity)." -Kind 'Success'
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# --- Initial population ------------------------------------------------------
$ui['NavList'].ItemsSource = @('Create OU', 'Create User', 'Create Group', 'Modify User', 'Archive User')
$ui['NavList'].SelectedIndex = 0

$ui['GroupScopeCombo'].ItemsSource = @('Global', 'DomainLocal', 'Universal')
$ui['GroupScopeCombo'].SelectedIndex = 0
$ui['GroupCategoryCombo'].ItemsSource = @('Security', 'Distribution')
$ui['GroupCategoryCombo'].SelectedIndex = 0

try {
    $domain = Get-AdtDefaultSearchBase
    $ui['DomainLabel'].Text = "Domain: $domain"
} catch {
    $ui['DomainLabel'].Text = 'Domain: unavailable'
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    Show-AdtMessage -Text ("Could not read the Active Directory domain.`n`n{0}" -f $_.Exception.Message) -Kind 'Error'
}

try {
    Sync-AdtOuCombos
    Sync-AdtUserGroupList
    Write-AdtStatus -Text 'Ready.'
} catch {
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
}

# --- Run ---------------------------------------------------------------------
[void]$window.ShowDialog()
