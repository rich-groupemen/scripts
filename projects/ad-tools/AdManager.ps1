#Requires -Version 5.1
<#
.SYNOPSIS
    Gestionnaire interactif des unités d'organisation (OU) et des utilisateurs AD.
.DESCRIPTION
    Interface WPF style Windows 11, sans dépendance externe, pour le projet
    AD Tools. Toute la logique AD vit dans lib/AdTools/AdTools.psm1 ; ce
    fichier n'est que la coquille.

    Les actions s'accumulent dans une file d'attente. Rien n'est écrit dans
    l'annuaire tant que l'opérateur n'a pas relu le plan complet et cliqué sur
    Tout appliquer. La file contient le plan entièrement résolu au moment de
    l'ajout : ce qui est relu est exactement ce qui s'exécute.

    Règles de conception :
      - Windows PowerShell 5.1 uniquement (exception au règle PS7 du dépôt).
      - Application STA, uniquement PresentationFramework/PresentationCore/
        WindowsBase. Aucune bibliothèque de thème tierce ; le style Fluent est
        du XAML écrit à la main.
      - Une saisie à la fois dans l'interface. Pas d'import CSV en masse.
      - Archiver signifie uniquement désactiver. Les groupes sont reportés.
      - Le mot de passe en clair est volontairement affiché à l'écran et écrit
        uniquement dans le fichier de transmission. Il n'est jamais journalisé.
.NOTES
    À lancer avec Windows PowerShell 5.1 sur un poste disposant du module
    ActiveDirectory (RSAT), avec un compte de domaine. Labo uniquement ; ne
    jamais viser la production.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RecordDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --- Garde STA ----------------------------------------------------------------
# WPF exige un appartement mono-thread. Si nous sommes lancés depuis une hôte
# MTA, nous relançons en STA et nous quittons cette instance.
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

# --- Assemblies et modules ---------------------------------------------------
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
        "Le module ActiveDirectory (RSAT) n'est pas disponible.`n`nInstallez-le depuis une invite élevée avec :`n  Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0`n`nDétail : $($_.Exception.Message)",
        'Outils AD', [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
    return
}

# --- XAML --------------------------------------------------------------------
$xaml = @'
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Outils AD"
    Height="820" Width="1300"
    MinHeight="680" MinWidth="1140"
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
                <TextBlock Text="Outils AD" FontSize="22" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}" />
                <TextBlock x:Name="DomainLabel" Text="Domaine : (chargement...)" FontSize="13" Foreground="{StaticResource MutedBrush}" Margin="0,2,0,0" />
            </StackPanel>
        </Border>

        <Grid Grid.Row="1">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="210" />
                <ColumnDefinition Width="*" />
                <ColumnDefinition Width="360" />
            </Grid.ColumnDefinitions>

            <Border Grid.Column="0" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,0,1,0">
                <ListBox x:Name="NavList" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource NavItem}" />
            </Border>

            <Grid Grid.Column="1">
                <ScrollViewer x:Name="PanelOu" VerticalScrollBarVisibility="Auto">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer une OU" />
                        <TextBlock Text="Crée une OU et, si vous le souhaitez, une agence par succursale ainsi qu'un département par agence. Rien n'est créé avant Tout appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="OuLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence" />
                                <ComboBox x:Name="OuLvl2" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Département" />
                                <ComboBox x:Name="OuLvl3" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Nom de la nouvelle OU" />
                                <TextBox x:Name="OuNameBox" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des agences (un par ligne, facultatif)" />
                                <TextBox x:Name="OuAgencesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des départements pour chaque agence (un par ligne, facultatif)" />
                                <TextBox x:Name="OuDepartmentsBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="OuAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="OuPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelAgence" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Ajouter une agence" />
                        <TextBlock Text="Ajoute une OU par agence sous un conteneur existant ou en attente. Rien n'est créé avant Tout appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="AgLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence" />
                                <ComboBox x:Name="AgLvl2" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Département" />
                                <ComboBox x:Name="AgLvl3" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des agences (un par ligne)" />
                                <TextBox x:Name="AgNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="88" VerticalScrollBarVisibility="Auto" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des départements pour chaque agence (un par ligne, facultatif)" />
                                <TextBox x:Name="AgDepartmentsBox" AcceptsReturn="True" TextWrapping="Wrap" Height="72" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="AgAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="AgPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelDepartment" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Ajouter un département" />
                        <TextBlock Text="Ajoute une OU par département sous une agence. Les utilisateurs vivent dans les OU de département. Rien n'est créé avant Tout appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="DepLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence" />
                                <ComboBox x:Name="DepLvl2" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Département" />
                                <ComboBox x:Name="DepLvl3" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des départements (un par ligne)" />
                                <TextBox x:Name="DepNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="88" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="DepAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="DepPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelUser" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer un utilisateur" />
                        <TextBlock Text="Ajoute un utilisateur dans un département. Le mot de passe est écrit dans le fichier de transmission en cas de succès. Rien n'est créé avant Tout appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="UserLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence" />
                                <ComboBox x:Name="UserLvl2" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Département" />
                                <ComboBox x:Name="UserLvl3" DisplayMemberPath="Name" />
                                <Grid Margin="0,10,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="16" />
                                        <ColumnDefinition Width="*" />
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Prénom" />
                                        <TextBox x:Name="UserGivenBox" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Nom" />
                                        <TextBox x:Name="UserSurnameBox" />
                                    </StackPanel>
                                </Grid>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Identifiant (calculé)" />
                                <TextBox x:Name="UserSamBox" IsReadOnly="True" Background="{StaticResource FieldBrush}" />
                                <Grid Margin="0,14,0,0">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="16" />
                                        <ColumnDefinition Width="*" />
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <Button x:Name="UserGeneratePasswordButton" Style="{StaticResource SecondaryButton}" Content="Générer le mot de passe" Margin="0" HorizontalAlignment="Left" />
                                    </StackPanel>
                                    <StackPanel Grid.Column="2">
                                        <TextBlock Style="{StaticResource FieldLabel}" Text="Mot de passe (affiché en clair volontairement)" Margin="0,0,0,4" />
                                        <TextBox x:Name="UserPasswordBox" IsReadOnly="True" Background="{StaticResource FieldBrush}" FontFamily="Consolas" />
                                    </StackPanel>
                                </Grid>
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="UserAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="UserPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="110" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelArchive" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Archiver un utilisateur" />
                        <TextBlock Text="Ajoute une désactivation de compte. L'utilisateur n'est ni supprimé ni déplacé. Rien n'est fait avant Tout appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Utilisateur (SamAccountName)" />
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*" />
                                        <ColumnDefinition Width="8" />
                                        <ColumnDefinition Width="Auto" />
                                    </Grid.ColumnDefinitions>
                                    <TextBox Grid.Column="0" x:Name="ArchiveUserBox" />
                                    <Button Grid.Column="2" x:Name="ArchiveLoadButton" Style="{StaticResource SecondaryButton}" Content="Charger" Margin="0" />
                                </Grid>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Compte" />
                                <TextBox x:Name="ArchiveInfoText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" Background="{StaticResource FieldBrush}" BorderThickness="0" MinHeight="70" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="ArchiveAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="ArchivePreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="90" Background="{StaticResource FieldBrush}" BorderThickness="0" />
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
                        <TextBlock Text="File d'attente" FontSize="18" FontWeight="SemiBold" Foreground="{StaticResource TextBrush}" />
                        <TextBlock x:Name="QueueCountText" Text="Rien en attente." FontSize="13" Foreground="{StaticResource MutedBrush}" Margin="0,2,0,0" />
                    </StackPanel>

                    <ListBox Grid.Row="1" x:Name="QueueList" Margin="0,12,0,0" DisplayMemberPath="Label" FontFamily="Consolas" FontSize="11" />

                    <StackPanel Grid.Row="2" Margin="0,12,0,0">
                        <StackPanel Orientation="Horizontal">
                            <Button x:Name="QueueApplyButton" Style="{StaticResource PrimaryButton}" Content="Tout appliquer" IsEnabled="False" />
                            <Button x:Name="QueueRemoveButton" Style="{StaticResource SecondaryButton}" Content="Supprimer" IsEnabled="False" />
                        </StackPanel>
                        <Button x:Name="QueueClearButton" Style="{StaticResource SecondaryButton}" Content="Vider la file" HorizontalAlignment="Left" Margin="0,8,0,0" />
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>

        <Border Grid.Row="2" Background="{StaticResource CardBrush}" BorderBrush="{StaticResource CardBorderBrush}" BorderThickness="0,1,0,0" Padding="20,10">
            <TextBlock x:Name="StatusText" Text="Prêt." FontSize="13" Foreground="{StaticResource MutedBrush}" TextWrapping="Wrap" />
        </Border>
    </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

# --- Prises sur les contrôles ------------------------------------------------
# Chaque contrôle nommé est collecté une seule fois afin que les gestionnaires
# restent lisibles et que nous n'ayons pas à répéter FindName.
$ui = @{}
foreach ($name in @(
        'DomainLabel', 'StatusText', 'NavList',
        'PanelOu', 'PanelAgence', 'PanelDepartment', 'PanelUser', 'PanelArchive',
        'OuLvl1', 'OuLvl2', 'OuLvl3', 'OuNameBox', 'OuAgencesBox', 'OuDepartmentsBox',
        'OuAddButton', 'OuPreviewText',
        'AgLvl1', 'AgLvl2', 'AgLvl3', 'AgNamesBox', 'AgDepartmentsBox', 'AgAddButton', 'AgPreviewText',
        'DepLvl1', 'DepLvl2', 'DepLvl3', 'DepNamesBox', 'DepAddButton', 'DepPreviewText',
        'UserLvl1', 'UserLvl2', 'UserLvl3', 'UserGivenBox', 'UserSurnameBox', 'UserSamBox',
        'UserGeneratePasswordButton', 'UserPasswordBox', 'UserAddButton', 'UserPreviewText',
        'ArchiveUserBox', 'ArchiveLoadButton', 'ArchiveInfoText', 'ArchiveAddButton', 'ArchivePreviewText',
        'QueueList', 'QueueCountText', 'QueueApplyButton', 'QueueRemoveButton', 'QueueClearButton'
    )) {
    $ui[$name] = $window.FindName($name)
}

# --- État --------------------------------------------------------------------
# La file contient des plans entièrement résolus. Une OU mise en file peut être
# choisie comme parent d'une action ultérieure : un parent est donc toujours mis
# en file avant son enfant, et l'ordre d'exécution est sûr.
$script:queue = New-Object System.Collections.Generic.List[object]
$script:existingOus = @()
$script:ouNodes = @()
$script:rootDn = ''
$script:syncingCascade = $false
$script:generatedPassword = $null
$script:archiveUser = $null
$script:recordDirectory = $RecordDirectory

# --- Aides à la manipulation des DN ------------------------------------------
function Get-AdtDnParts {
    # Découpe un DN en ses RDN, en respectant les virgules échappées.
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$DistinguishedName
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder
    for ($i = 0; $i -lt $DistinguishedName.Length; $i++) {
        $character = $DistinguishedName[$i]
        if ($character -eq '\' -and ($i + 1) -lt $DistinguishedName.Length) {
            [void]$current.Append($character)
            [void]$current.Append($DistinguishedName[$i + 1])
            $i++
            continue
        }
        if ($character -eq ',') {
            $parts.Add($current.ToString())
            [void]$current.Clear()
            continue
        }
        [void]$current.Append($character)
    }
    if ($current.Length -gt 0) {
        $parts.Add($current.ToString())
    }
    return [string[]]$parts.ToArray()
}

function Get-AdtDnValue {
    # Renvoie la valeur du premier RDN : "OU=RH,OU=Lyon,..." -> "RH".
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$DistinguishedName
    )

    $parts = @(Get-AdtDnParts -DistinguishedName $DistinguishedName)
    if ($parts.Count -eq 0) {
        return $DistinguishedName
    }
    $first = $parts[0]
    $separator = $first.IndexOf('=')
    if ($separator -lt 0) {
        return $first
    }
    return $first.Substring($separator + 1).Replace('\,', ',').Replace('\\', '\')
}

function Get-AdtDnParent {
    # Renvoie le DN du parent, ou une chaîne vide pour la racine.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$DistinguishedName
    )

    $parts = @(Get-AdtDnParts -DistinguishedName $DistinguishedName)
    if ($parts.Count -le 1) {
        return ''
    }
    return [string]($parts[1..($parts.Count - 1)] -join ',')
}

function Get-AdtDnDisplayPath {
    # Convertit un DN en chemin lisible : "Entreprises / Lyon / RH".
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$DistinguishedName
    )

    $names = New-Object System.Collections.Generic.List[string]
    foreach ($part in @(Get-AdtDnParts -DistinguishedName $DistinguishedName)) {
        $separator = $part.IndexOf('=')
        if ($separator -lt 0) {
            continue
        }
        $type = $part.Substring(0, $separator)
        if ($type -eq 'OU' -or $type -eq 'CN') {
            $value = $part.Substring($separator + 1).Replace('\,', ',').Replace('\\', '\')
            $names.Insert(0, $value)
        }
    }
    if ($names.Count -eq 0) {
        return $DistinguishedName
    }
    return [string]($names -join ' / ')
}

# --- Aides d'interface -------------------------------------------------------
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
        [string]$Title = 'Outils AD',

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
        [string]$Title = 'Confirmation'
    )

    $result = [System.Windows.MessageBox]::Show(
        $Text, $Title, [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
    return [bool]($result -eq [System.Windows.MessageBoxResult]::Yes)
}

function Get-AdtMultilineItems {
    # Découpe une zone de texte multi-lignes en une liste sans doublon.
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
    # DN des OU mises en file mais pas encore créées.
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

# --- Arborescence des OU -----------------------------------------------------
function Sync-AdtOuTree {
    # Reconstruit la liste des nœuds (réels + en attente) et resynchronise les
    # quatre cascades.
    [CmdletBinding()]
    param()

    try {
        $script:existingOus = @(Get-AdtOU)
    } catch {
        $script:existingOus = @()
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    }

    try {
        $script:rootDn = [string](Get-AdtDefaultSearchBase)
    } catch {
        $script:rootDn = ''
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    }

    $nodes = New-Object System.Collections.Generic.List[object]
    if ($script:rootDn) {
        $nodes.Add([pscustomobject]@{
                DistinguishedName = $script:rootDn
                Name = '(racine du domaine)'
                ParentDn = ''
                Pending = $false
                IsRoot = $true
            })
    }
    foreach ($ou in $script:existingOus) {
        $dn = [string]$ou.DistinguishedName
        $nodes.Add([pscustomobject]@{
                DistinguishedName = $dn
                Name = Get-AdtDnValue -DistinguishedName $dn
                ParentDn = Get-AdtDnParent -DistinguishedName $dn
                Pending = $false
                IsRoot = $false
            })
    }
    foreach ($dn in Get-AdtPendingOuPaths) {
        if (-not ($nodes | Where-Object { $_.DistinguishedName -eq $dn })) {
            $nodes.Add([pscustomobject]@{
                    DistinguishedName = $dn
                    Name = '{0} (en attente)' -f (Get-AdtDnValue -DistinguishedName $dn)
                    ParentDn = Get-AdtDnParent -DistinguishedName $dn
                    Pending = $true
                    IsRoot = $false
                })
        }
    }
    $script:ouNodes = @($nodes)

    Sync-AdtCascade -First 'OuLvl1' -Second 'OuLvl2' -Third 'OuLvl3'
    Sync-AdtCascade -First 'AgLvl1' -Second 'AgLvl2' -Third 'AgLvl3'
    Sync-AdtCascade -First 'DepLvl1' -Second 'DepLvl2' -Third 'DepLvl3'
    Sync-AdtCascade -First 'UserLvl1' -Second 'UserLvl2' -Third 'UserLvl3'
}

function Sync-AdtCascade {
    # Remplit une cascade à trois niveaux. Le niveau 1 propose la racine du
    # domaine puis les établissements ; chaque niveau suivant propose les
    # enfants de la sélection du niveau précédent.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$First,

        [Parameter(Mandatory = $true)]
        [string]$Second,

        [Parameter(Mandatory = $true)]
        [string]$Third
    )

    $script:syncingCascade = $true
    try {
        $c1 = $ui[$First]
        $c2 = $ui[$Second]
        $c3 = $ui[$Third]

        $previous1 = $null
        if ($c1.SelectedItem) {
            $previous1 = [string]$c1.SelectedItem.DistinguishedName
        }
        $previous2 = $null
        if ($c2.SelectedItem) {
            $previous2 = [string]$c2.SelectedItem.DistinguishedName
        }
        $previous3 = $null
        if ($c3.SelectedItem) {
            $previous3 = [string]$c3.SelectedItem.DistinguishedName
        }

        $level1 = @($script:ouNodes | Where-Object { $_.IsRoot -or $_.ParentDn -eq $script:rootDn })
        $c1.ItemsSource = $level1
        $match1 = $level1 | Where-Object { $_.DistinguishedName -eq $previous1 } | Select-Object -First 1
        if ($match1) {
            $c1.SelectedItem = $match1
        } elseif ($level1.Count -gt 0) {
            $c1.SelectedIndex = 0
        }

        $children1 = @()
        if ($c1.SelectedItem) {
            $children1 = @($script:ouNodes | Where-Object {
                    -not $_.IsRoot -and $_.ParentDn -eq $c1.SelectedItem.DistinguishedName })
        }
        $c2.ItemsSource = $children1
        $match2 = $children1 | Where-Object { $_.DistinguishedName -eq $previous2 } | Select-Object -First 1
        if ($match2) {
            $c2.SelectedItem = $match2
        } elseif ($children1.Count -gt 0) {
            $c2.SelectedIndex = 0
        }

        $children2 = @()
        if ($c2.SelectedItem) {
            $children2 = @($script:ouNodes | Where-Object {
                    -not $_.IsRoot -and $_.ParentDn -eq $c2.SelectedItem.DistinguishedName })
        }
        $c3.ItemsSource = $children2
        $match3 = $children2 | Where-Object { $_.DistinguishedName -eq $previous3 } | Select-Object -First 1
        if ($match3) {
            $c3.SelectedItem = $match3
        } elseif ($children2.Count -gt 0) {
            $c3.SelectedIndex = 0
        }
    } finally {
        $script:syncingCascade = $false
    }
}

function Get-AdtCascadeSelection {
    # Le parent effectif est la sélection la plus profonde non vide.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$First,

        [Parameter(Mandatory = $true)]
        [string]$Second,

        [Parameter(Mandatory = $true)]
        [string]$Third
    )

    foreach ($name in @($Third, $Second, $First)) {
        $item = $ui[$name].SelectedItem
        if ($item -and -not $item.IsRoot) {
            return [string]$item.DistinguishedName
        }
    }
    return [string]$script:rootDn
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
    # Relie la liste de la file et aligne les boutons sur son contenu.
    [CmdletBinding()]
    param()

    $ui['QueueList'].ItemsSource = $null
    $ui['QueueList'].ItemsSource = $script:queue

    $count = $script:queue.Count
    if ($count -eq 0) {
        $ui['QueueCountText'].Text = 'Rien en attente.'
    } else {
        $ui['QueueCountText'].Text = "{0} action(s) en attente." -f $count
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
    Sync-AdtOuTree
}

function Sync-AdtArchiveUser {
    [CmdletBinding()]
    param()

    try {
        $identity = $ui['ArchiveUserBox'].Text.Trim()
        if (-not $identity) {
            Show-AdtMessage -Text 'Saisissez un utilisateur (SamAccountName) à charger.' -Kind 'Warning'
            return
        }

        $script:archiveUser = Get-AdtUser -Identity $identity
        $state = 'Activé'
        if (-not $script:archiveUser.Enabled) {
            $state = 'Déjà désactivé'
        }

        $lines = @(
            "Identifiant    : $($script:archiveUser.SamAccountName)"
            "Nom affiché    : $($script:archiveUser.DisplayName)"
            "DN             : $($script:archiveUser.DistinguishedName)"
            "État           : $state"
        )
        $ui['ArchiveInfoText'].Text = ($lines -join [Environment]::NewLine)
        Write-AdtStatus -Text "$($script:archiveUser.SamAccountName) chargé."
    } catch {
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
    }
}

# --- Construction de la file -------------------------------------------------
function Add-AdtOuPlan {
    # Met en file une OU, puis éventuellement une OU par agence et une par
    # département sous chaque agence.
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
    $topDn = "OU=$Name,$ParentPath"
    Add-AdtQueueItem -Item ([pscustomobject]@{
            Kind = 'OU'
            Name = $Name
            ParentPath = $ParentPath
            DistinguishedName = $topDn
            Label = "OU     $(Get-AdtDnDisplayPath -DistinguishedName $topDn)"
        })
    $queued.Add($topDn)

    foreach ($agence in $Agences) {
        $agenceDn = "OU=$agence,$topDn"
        Add-AdtQueueItem -Item ([pscustomobject]@{
                Kind = 'OU'
                Name = $agence
                ParentPath = $topDn
                DistinguishedName = $agenceDn
                Label = "OU     $(Get-AdtDnDisplayPath -DistinguishedName $agenceDn)"
            })
        $queued.Add($agenceDn)

        foreach ($department in $Departments) {
            $departmentDn = "OU=$department,$agenceDn"
            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'OU'
                    Name = $department
                    ParentPath = $agenceDn
                    DistinguishedName = $departmentDn
                    Label = "OU     $(Get-AdtDnDisplayPath -DistinguishedName $departmentDn)"
                })
            $queued.Add($departmentDn)
        }
    }

    return [string[]]$queued.ToArray()
}

# --- Exécution par lot -------------------------------------------------------
function Invoke-AdtQueue {
    # Exécute la file dans l'ordre des dépendances : toutes les OU d'abord (dans
    # l'ordre de la file, donc un parent avant son enfant), puis les
    # utilisateurs, puis les archivages.
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

# --- Câblage des événements --------------------------------------------------

$ui['NavList'].Add_SelectionChanged({ Sync-AdtPanelVisibility })

# Chaque cascade porte son identifiant dans le Tag du contrôle. Le gestionnaire
# unique lit $this.Tag : ainsi il n'y a ni variable capturée ni GetNewClosure,
# et $script:syncingCascade continue de désigner la portée du script. C'est ce
# drapeau qui empêche la boucle de réentrée pendant qu'un niveau se remplit et
# redéclenche SelectionChanged.
$script:cascadeGroups = @(
    @{ First = 'OuLvl1'; Second = 'OuLvl2'; Third = 'OuLvl3' },
    @{ First = 'AgLvl1'; Second = 'AgLvl2'; Third = 'AgLvl3' },
    @{ First = 'DepLvl1'; Second = 'DepLvl2'; Third = 'DepLvl3' },
    @{ First = 'UserLvl1'; Second = 'UserLvl2'; Third = 'UserLvl3' }
)
foreach ($group in $script:cascadeGroups) {
    foreach ($controlName in @($group.First, $group.Second, $group.Third)) {
        $ui[$controlName].Tag = $group
        $ui[$controlName].Add_SelectionChanged({
                if ($script:syncingCascade) {
                    return
                }
                $current = $this.Tag
                Sync-AdtCascade -First $current.First -Second $current.Second -Third $current.Third
            })
    }
}

# Créer une OU
$ui['OuAddButton'].Add_Click({
        try {
            $name = $ui['OuNameBox'].Text.Trim()
            if (-not $name) {
                Show-AdtMessage -Text 'Saisissez un nom pour la nouvelle OU.' -Kind 'Warning'
                return
            }
            $parentDn = Get-AdtCascadeSelection -First 'OuLvl1' -Second 'OuLvl2' -Third 'OuLvl3'
            if (-not $parentDn) {
                Show-AdtMessage -Text 'Choisissez un conteneur parent.' -Kind 'Warning'
                return
            }

            $agences = @(Get-AdtMultilineItems -Text $ui['OuAgencesBox'].Text)
            $departments = @(Get-AdtMultilineItems -Text $ui['OuDepartmentsBox'].Text)

            $queued = Add-AdtOuPlan -Name $name -ParentPath $parentDn -Agences $agences -Departments $departments
            $ui['OuPreviewText'].Text = ($queued | ForEach-Object { Get-AdtDnDisplayPath -DistinguishedName $_ }) -join [Environment]::NewLine
            $ui['OuNameBox'].Text = ''
            $ui['OuAgencesBox'].Text = ''
            $ui['OuDepartmentsBox'].Text = ''
            Write-AdtStatus -Text ("{0} OU ajoutée(s) à la file. Vérifiez la file puis cliquez sur Tout appliquer." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Ajouter une agence
$ui['AgAddButton'].Add_Click({
        try {
            $parentDn = Get-AdtCascadeSelection -First 'AgLvl1' -Second 'AgLvl2' -Third 'AgLvl3'
            if (-not $parentDn) {
                Show-AdtMessage -Text 'Choisissez un conteneur parent.' -Kind 'Warning'
                return
            }
            $agences = @(Get-AdtMultilineItems -Text $ui['AgNamesBox'].Text)
            if ($agences.Count -eq 0) {
                Show-AdtMessage -Text 'Saisissez au moins un nom d''agence.' -Kind 'Warning'
                return
            }
            $departments = @(Get-AdtMultilineItems -Text $ui['AgDepartmentsBox'].Text)

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($agence in $agences) {
                $queued.AddRange([string[]](Add-AdtOuPlan -Name $agence -ParentPath $parentDn -Departments $departments))
            }
            $ui['AgPreviewText'].Text = ($queued | ForEach-Object { Get-AdtDnDisplayPath -DistinguishedName $_ }) -join [Environment]::NewLine
            $ui['AgNamesBox'].Text = ''
            $ui['AgDepartmentsBox'].Text = ''
            Write-AdtStatus -Text ("{0} OU ajoutée(s) à la file. Vérifiez la file puis cliquez sur Tout appliquer." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Ajouter un département
$ui['DepAddButton'].Add_Click({
        try {
            $parentDn = Get-AdtCascadeSelection -First 'DepLvl1' -Second 'DepLvl2' -Third 'DepLvl3'
            if (-not $parentDn) {
                Show-AdtMessage -Text 'Choisissez un conteneur parent.' -Kind 'Warning'
                return
            }
            $departments = @(Get-AdtMultilineItems -Text $ui['DepNamesBox'].Text)
            if ($departments.Count -eq 0) {
                Show-AdtMessage -Text 'Saisissez au moins un nom de département.' -Kind 'Warning'
                return
            }

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($department in $departments) {
                $dn = "OU=$department,$parentDn"
                Add-AdtQueueItem -Item ([pscustomobject]@{
                        Kind = 'OU'
                        Name = $department
                        ParentPath = $parentDn
                        DistinguishedName = $dn
                        Label = "OU     $(Get-AdtDnDisplayPath -DistinguishedName $dn)"
                    })
                $queued.Add($dn)
            }
            $ui['DepPreviewText'].Text = ($queued | ForEach-Object { Get-AdtDnDisplayPath -DistinguishedName $_ }) -join [Environment]::NewLine
            $ui['DepNamesBox'].Text = ''
            Write-AdtStatus -Text ("{0} OU ajoutée(s) à la file. Vérifiez la file puis cliquez sur Tout appliquer." -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Créer un utilisateur
$ui['UserGivenBox'].Add_TextChanged({ Sync-AdtSamPreview })
$ui['UserSurnameBox'].Add_TextChanged({ Sync-AdtSamPreview })

$ui['UserGeneratePasswordButton'].Add_Click({
        try {
            $generated = New-AdtPassword
            $script:generatedPassword = [string]$generated.Password
            $ui['UserPasswordBox'].Text = $script:generatedPassword
            Write-AdtStatus -Text 'Mot de passe généré.'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['UserAddButton'].Add_Click({
        try {
            $given = $ui['UserGivenBox'].Text.Trim()
            $surname = $ui['UserSurnameBox'].Text.Trim()
            if (-not $given -or -not $surname) {
                Show-AdtMessage -Text 'Saisissez un prénom et un nom.' -Kind 'Warning'
                return
            }
            $path = Get-AdtCascadeSelection -First 'UserLvl1' -Second 'UserLvl2' -Third 'UserLvl3'
            if (-not $path) {
                Show-AdtMessage -Text 'Choisissez un département.' -Kind 'Warning'
                return
            }

            if (-not $script:generatedPassword) {
                $generated = New-AdtPassword
                $script:generatedPassword = [string]$generated.Password
                $ui['UserPasswordBox'].Text = $script:generatedPassword
            }

            $sam = Get-AdtSamAccountName -GivenName $given -Surname $surname
            $displayPath = Get-AdtDnDisplayPath -DistinguishedName $path

            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'User'
                    GivenName = $given
                    Surname = $surname
                    SamAccountName = $sam
                    Path = $path
                    Password = $script:generatedPassword
                    Label = "UTIL   $sam -> $displayPath   mdp=$script:generatedPassword"
                })

            $ui['UserPreviewText'].Text = (
                "Utilisateur ajouté : " +
                [Environment]::NewLine + "  Nom complet  : $given $surname" +
                [Environment]::NewLine + "  Identifiant  : $sam" +
                [Environment]::NewLine + "  Département  : $displayPath" +
                [Environment]::NewLine + "  Mot de passe : $script:generatedPassword" +
                [Environment]::NewLine + "  Changement de mot de passe à la première connexion : non"
            )

            $script:generatedPassword = $null
            $ui['UserPasswordBox'].Text = ''
            $ui['UserGivenBox'].Text = ''
            $ui['UserSurnameBox'].Text = ''
            $ui['UserSamBox'].Text = ''
            Write-AdtStatus -Text "$sam ajouté à la file. Vérifiez la file puis cliquez sur Tout appliquer." -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Archiver un utilisateur
$ui['ArchiveLoadButton'].Add_Click({ Sync-AdtArchiveUser })

$ui['ArchiveAddButton'].Add_Click({
        try {
            if (-not $script:archiveUser) {
                Show-AdtMessage -Text 'Chargez d''abord un utilisateur.' -Kind 'Warning'
                return
            }
            $sam = [string]$script:archiveUser.SamAccountName
            Add-AdtQueueItem -Item ([pscustomobject]@{
                    Kind = 'Archive'
                    Identity = $sam
                    Label = "ARCH  $sam"
                })
            $ui['ArchivePreviewText'].Text = "Désactivation de '$sam' ajoutée à la file."
            $ui['ArchiveUserBox'].Text = ''
            $ui['ArchiveInfoText'].Text = ''
            $script:archiveUser = $null
            Write-AdtStatus -Text "Désactivation de $sam ajoutée à la file. Vérifiez la file puis cliquez sur Tout appliquer." -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Contrôles de la file
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
            Sync-AdtOuTree
            Write-AdtStatus -Text ("{0} action(s) supprimée(s) de la file." -f $selected.Count)
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        }
    })

$ui['QueueClearButton'].Add_Click({
        $script:queue.Clear()
        Sync-AdtQueue
        Sync-AdtOuTree
        Write-AdtStatus -Text 'File vidée.'
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
            $body = "Appliquer ces {0} action(s) à l'annuaire ?`n`n{1}" -f $script:queue.Count, ($summary -join [Environment]::NewLine)
            if (-not (Confirm-AdtAction -Text $body -Title 'Tout appliquer')) {
                return
            }

            $result = Invoke-AdtQueue
            $script:queue.Clear()
            Sync-AdtQueue
            Sync-AdtOuTree

            $lines = @(
                "Réussies  : $($result.Succeeded)"
                "Échouées  : $($result.Failed)"
            )
            if ($result.UsersCreated -gt 0) {
                $lines += ''
                $lines += "Fichier de transmission : $($result.RecordPath)"
                $lines += 'Ce fichier est en clair. Remettez-le à l''utilisateur puis supprimez-le.'
                $lines += 'Ne le commitez jamais et ne le laissez jamais dans le dépôt.'
            }
            if ($result.Failed -gt 0) {
                $lines += ''
                $lines += 'Échecs :'
                foreach ($failure in $result.Failures) {
                    $lines += "  $failure"
                }
            }

            $icon = [System.Windows.MessageBoxImage]::Information
            if ($result.Failed -gt 0) {
                $icon = [System.Windows.MessageBoxImage]::Warning
            }
            [void][System.Windows.MessageBox]::Show(
                ($lines -join [Environment]::NewLine), 'Tout appliquer',
                [System.Windows.MessageBoxButton]::OK, $icon)

            if ($result.Failed -gt 0) {
                Write-AdtStatus -Text ("{0} action(s) appliquée(s), {1} en échec." -f $result.Succeeded, $result.Failed) -Kind 'Error'
            } else {
                Write-AdtStatus -Text ("{0} action(s) appliquée(s)." -f $result.Succeeded) -Kind 'Success'
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# --- Initialisation ----------------------------------------------------------
$ui['NavList'].ItemsSource = @('Créer une OU', 'Ajouter une agence', 'Ajouter un département', 'Créer un utilisateur', 'Archiver un utilisateur')
$ui['NavList'].SelectedIndex = 0

try {
    $domain = Get-AdtDefaultSearchBase
    $ui['DomainLabel'].Text = "Domaine : $domain"
} catch {
    $ui['DomainLabel'].Text = 'Domaine : indisponible'
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
    Show-AdtMessage -Text ("Impossible de lire le domaine Active Directory.`n`n{0}" -f $_.Exception.Message) -Kind 'Error'
}

try {
    Sync-AdtOuTree
    Sync-AdtQueue
    Write-AdtStatus -Text 'Prêt.'
} catch {
    Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
}

# --- Exécution ---------------------------------------------------------------
[void]$window.ShowDialog()
