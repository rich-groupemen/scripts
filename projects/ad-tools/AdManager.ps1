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
    Appliquer. La file contient le plan entièrement résolu au moment de
    l'ajout : ce qui est relu est exactement ce qui s'exécute.

    Chaque section ne propose que les sélecteurs dont elle a besoin :

      - Créer un OU        : un nom seul. L'OU est créée à la racine du
                             domaine, au premier niveau.
      - Créer une agence   : choisir l'établissement, puis un nom par agence.
      - Créer un départem. : choisir l'établissement puis l'agence, puis un
                             nom par département.
      - Créer un utilisateur : choisir les trois niveaux dans l'ordre, puis
                             les identités.

    Les OU mises en file mais pas encore créées apparaissent dans les listes
    avec la mention « (en attente) » : un opérateur peut donc préparer tout un
    nouveau site — OU, agences, départements, utilisateurs — avant la première
    écriture dans l'annuaire.

    Règles de conception :
      - Windows PowerShell 5.1 uniquement (exception à la règle PS7 du dépôt).
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

        <Style x:Key="Hint" TargetType="TextBlock">
            <Setter Property="Margin" Value="0,4,0,0" />
            <Setter Property="Foreground" Value="{StaticResource MutedBrush}" />
            <Setter Property="FontSize" Value="12" />
            <Setter Property="FontStyle" Value="Italic" />
            <Setter Property="TextWrapping" Value="Wrap" />
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
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer un OU" />
                        <TextBlock Text="Crée une unité d'organisation au premier niveau, directement sous la racine du domaine. C'est la première étape pour ouvrir un nouvel établissement. Rien n'est créé avant Appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Créée sous" />
                                <TextBox x:Name="OuParentText" IsReadOnly="True" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Nom de la nouvelle OU" />
                                <TextBox x:Name="OuNameBox" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="OuAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="OuPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="70" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelAgence" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer une agence" />
                        <TextBlock Text="Ajoute une agence par nom sous l'établissement choisi. Rien n'est créé avant Appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement (où créer l'agence)" />
                                <ComboBox x:Name="AgLvl1" DisplayMemberPath="Name" />
                                <TextBlock x:Name="AgHintText" Style="{StaticResource Hint}" Text="Aucun établissement disponible. Créez-en d'abord un dans « Créer un OU »." Visibility="Collapsed" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des agences (un par ligne)" />
                                <TextBox x:Name="AgNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="96" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="AgAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="AgPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="70" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelDepartment" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer un département" />
                        <TextBlock Text="Ajoute un département par nom sous l'agence choisie. Les utilisateurs vivent dans les OU de département. Rien n'est créé avant Appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="DepLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence (où créer le département)" />
                                <ComboBox x:Name="DepLvl2" DisplayMemberPath="Name" />
                                <TextBlock x:Name="DepHintText" Style="{StaticResource Hint}" Text="Aucune agence disponible pour cet établissement. Créez-en d'abord une dans « Créer une agence »." Visibility="Collapsed" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Noms des départements (un par ligne)" />
                                <TextBox x:Name="DepNamesBox" AcceptsReturn="True" TextWrapping="Wrap" Height="96" VerticalScrollBarVisibility="Auto" />
                                <StackPanel Orientation="Horizontal" Margin="0,18,0,0">
                                    <Button x:Name="DepAddButton" Style="{StaticResource PrimaryButton}" Content="Ajouter à la file" />
                                </StackPanel>
                            </StackPanel>
                        </Border>
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Text="Ajouté par cette action" FontWeight="SemiBold" Margin="0,0,0,8" />
                                <TextBox x:Name="DepPreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="70" Background="{StaticResource FieldBrush}" BorderThickness="0" />
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </ScrollViewer>

                <ScrollViewer x:Name="PanelUser" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                    <StackPanel Margin="24">
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Créer un utilisateur" />
                        <TextBlock Text="Ajoute un utilisateur dans le département choisi. Le mot de passe est écrit dans le fichier de transmission en cas de succès. Rien n'est créé avant Appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
                        <Border Style="{StaticResource Card}">
                            <StackPanel>
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Établissement" />
                                <ComboBox x:Name="UserLvl1" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Agence" />
                                <ComboBox x:Name="UserLvl2" DisplayMemberPath="Name" />
                                <TextBlock Style="{StaticResource FieldLabel}" Text="Département (où vivra l'utilisateur)" />
                                <ComboBox x:Name="UserLvl3" DisplayMemberPath="Name" />
                                <TextBlock x:Name="UserHintText" Style="{StaticResource Hint}" Text="Aucun département disponible. Créez-en d'abord un dans « Créer un département »." Visibility="Collapsed" />
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
                        <TextBlock Text="Ajoute une désactivation de compte. L'utilisateur n'est ni supprimé ni déplacé. Rien n'est fait avant Appliquer." Foreground="{StaticResource MutedBrush}" Margin="0,0,0,12" TextWrapping="Wrap" />
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
                                <TextBox x:Name="ArchivePreviewText" IsReadOnly="True" TextWrapping="Wrap" AcceptsReturn="True" MinHeight="70" Background="{StaticResource FieldBrush}" BorderThickness="0" />
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
                            <Button x:Name="QueueApplyButton" Style="{StaticResource PrimaryButton}" Content="Appliquer" IsEnabled="False" />
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
        'OuParentText', 'OuNameBox', 'OuAddButton', 'OuPreviewText',
        'AgLvl1', 'AgHintText', 'AgNamesBox', 'AgAddButton', 'AgPreviewText',
        'DepLvl1', 'DepLvl2', 'DepHintText', 'DepNamesBox', 'DepAddButton', 'DepPreviewText',
        'UserLvl1', 'UserLvl2', 'UserLvl3', 'UserHintText',
        'UserGivenBox', 'UserSurnameBox', 'UserSamBox',
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
$script:syncingPickers = $false
$script:generatedPassword = $null
$script:archiveUser = $null
$script:recordDirectory = $RecordDirectory

# --- Aides à la manipulation des DN ------------------------------------------
function Get-AdtDnParts {
    # Découpe un DN en ses RDN, en respectant les virgules échappées.
    # La virgule précédée d'une barre oblique inverse est littérale et ne
    # sépare pas deux RDN.
    [CmdletBinding()]
    [OutputType([object[]])]
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
    # La virgule unaire (« , ») empêche PowerShell d'aplatir un tableau vide au
    # moment du return : sans elle, la fonction renverrait $null et le appelant
    # qui itère dessus échouerait sous StrictMode. PowerShell voit « , » en
    # object[] (d'où l'OutputType), le tableau réel livré est un string[].
    return , ([string[]]$parts.ToArray())
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

    # Get-AdtDnParts renvoie un tableau par la virgule unaire : l'affecter
    # directement (sans @(), qui l'empaîterait) donne le tableau réel.
    $parts = Get-AdtDnParts -DistinguishedName $DistinguishedName
    if ($parts.Count -eq 0) {
        return $DistinguishedName
    }
    $first = $parts[0]
    if ($null -eq $first) {
        return $DistinguishedName
    }
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

    $parts = Get-AdtDnParts -DistinguishedName $DistinguishedName
    if ($parts.Count -le 1) {
        return ''
    }
    # Un DN fait uniquement de composants DC= est la racine du domaine : il n'a
    # pas de parent.
    $hasContainer = $false
    foreach ($part in $parts) {
        if ($part -notmatch '^DC=') {
            $hasContainer = $true
            break
        }
    }
    if (-not $hasContainer) {
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
    $parts = Get-AdtDnParts -DistinguishedName $DistinguishedName
    foreach ($part in $parts) {
        if ($null -eq $part) {
            continue
        }
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
    # Découpe une zone de texte multi-lignes en une liste sans doublon ni
    # entrée vide.
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$Text
    )

    $items = New-Object System.Collections.Generic.List[string]
    $lines = @($Text -split "\r?\n")
    foreach ($line in $lines) {
        if ($null -eq $line) {
            continue
        }
        $name = $line.Trim()
        if ($name -and ($items -notcontains $name)) {
            $items.Add($name)
        }
    }
    # Virgule unaire : renvoyer un vrai tableau, même vide.
    return , ([string[]]$items.ToArray())
}

function Get-AdtPendingOuPaths {
    # DN des OU mises en file mais pas encore créées.
    [CmdletBinding()]
    [OutputType([object[]])]
    param()

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($item in $script:queue) {
        if ($item.Kind -eq 'OU') {
            $paths.Add([string]$item.DistinguishedName)
        }
    }
    # Virgule unaire (« , ») : une file vide doit renvoyer un vrai string[] et non
    # $null, sinon $x.Count et $x[0] sur l'appelant se comportent de façon
    # inattendue. Piège associé à ne jamais re-faire : @() appelé sur un
    # résultat de fonction renvoie un tableau empaîtenant le tableau (count 1) ;
    # les sites d'appel affectent donc directement, sans @().
    return , ([string[]]$paths.ToArray())
}

# --- Arborescence des OU -----------------------------------------------------
function Sync-AdtOuTree {
    # Reconstruit la liste des nœuds (réels + en attente) puis resynchronise
    # les sélecteurs.
    [CmdletBinding()]
    param()

    try {
        # On accumule dans une List[object] puis on convertit en tableau :
        # @(<List[object]>) lèverait "Argument types do not match", et @($null)
        # formerait un tableau d'un élément qui casserait la boucle suivante.
        $found = Get-AdtOU
        $buffer = New-Object System.Collections.Generic.List[object]
        foreach ($ou in $found) {
            if ($null -ne $ou) {
                [void]$buffer.Add($ou)
            }
        }
        $script:existingOus = $buffer.ToArray()
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

    $map = @{}
    foreach ($ou in $script:existingOus) {
        $dn = [string]$ou.DistinguishedName
        $map[$dn] = [pscustomobject]@{
            DistinguishedName = $dn
            Name = [string]$ou.Name
            ParentDn = Get-AdtDnParent -DistinguishedName $dn
            Pending = $false
        }
    }
    $pending = Get-AdtPendingOuPaths
    foreach ($dn in $pending) {
        if (-not $dn) {
            continue
        }
        if ($map.ContainsKey($dn)) {
            continue
        }
        $map[$dn] = [pscustomobject]@{
            DistinguishedName = $dn
            Name = '{0} (en attente)' -f (Get-AdtDnValue -DistinguishedName $dn)
            ParentDn = Get-AdtDnParent -DistinguishedName $dn
            Pending = $true
        }
    }
    # List[object] puis .ToArray() : donne toujours un vrai tableau, vide ou non.
    $nodes = New-Object System.Collections.Generic.List[object]
    foreach ($key in $map.Keys) {
        [void]$nodes.Add($map[$key])
    }
    $script:ouNodes = $nodes.ToArray()

    Sync-AdtPickers
}

function Sync-AdtPickerLevel {
    # Remplit un niveau d'un sélecteur. -TopLevel propose les établissements,
    # c'est-à-dire les OU dont le parent est la racine du domaine. Sinon sont
    # proposés les enfants directs du DN passé.
    #
    # -HintControlName, donné au niveau terminal d'une section, affiche le texte
    # d'aide « créez d'abord un… » quand la liste ressort vide.
    #
    # Le nom est Sync- et non Set- : la règle PSUseShouldProcessForStateChanging-
    # Functions exige SupportsShouldProcess pour tout verbe d'écriture, ce qui
    # n'a pas de sens pour de simples affichages.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ControlName,

        [Parameter()]
        [AllowEmptyString()]
        [string]$ParentDn,

        [Parameter()]
        [switch]$TopLevel,

        [Parameter()]
        [AllowEmptyString()]
        [string]$HintControlName
    )

    $control = $ui[$ControlName]
    $previous = $null
    if ($control.SelectedItem) {
        $previous = [string]$control.SelectedItem.DistinguishedName
    }

    if ($TopLevel) {
        $wanted = $script:rootDn
    } else {
        $wanted = $ParentDn
    }

    # List[object] puis .ToArray() : un sélecteur reçoit toujours un tableau
    # object[], vide compris — jamais $null, dont .Count poserait problème.
    $matched = New-Object System.Collections.Generic.List[object]
    if ($wanted) {
        foreach ($node in $script:ouNodes) {
            if ($node.ParentDn -eq $wanted) {
                [void]$matched.Add($node)
            }
        }
    }
    $items = $matched.ToArray()

    $control.ItemsSource = $items

    # On affecte toujours SelectedItem, jamais SelectedIndex : l'index suppose
    # que le ComboBox répercute immédiatement l'index sur l'élément, alors que
    # l'élément est la seule source de vérité pour Get-AdtSelectedDn.
    $match = $null
    foreach ($candidate in $items) {
        if ($candidate.DistinguishedName -eq $previous) {
            $match = $candidate
            break
        }
    }
    if ($null -eq $match -and $items.Count -gt 0) {
        $match = $items[0]
    }
    $control.SelectedItem = $match

    if ($HintControlName) {
        Sync-AdtHint -ControlName $HintControlName -Show ($items.Count -eq 0)
    }
}

function Sync-AdtHint {
    # Affiche ou masque le texte d'aide « créez d'abord un… » d'un niveau.
    # Isolée ici parce que seules la valeur Visibility de type WPF sont
    # encapsulées : Sync-AdtPickerLevel reste ainsi indépendante des assemblages
    # et reste testable sans fenêtre.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ControlName,

        [Parameter(Mandatory = $true)]
        [bool]$Show
    )

    if ($Show) {
        $ui[$ControlName].Visibility = [System.Windows.Visibility]::Visible
    } else {
        $ui[$ControlName].Visibility = [System.Windows.Visibility]::Collapsed
    }
}

function Sync-AdtPickers {
    # Remplit les sélecteurs des trois sections. Le drapeau empêche la boucle de
    # réentrée : changer un niveau redéclenche SelectionChanged, ce qui
    # rappellerait cette fonction indéfiniment sans le garde-fou.
    [CmdletBinding()]
    param()

    $script:syncingPickers = $true
    try {
        # Créer une agence : un seul niveau.
        Sync-AdtPickerLevel -ControlName 'AgLvl1' -TopLevel -HintControlName 'AgHintText'

        # Créer un département : établissement puis agence.
        Sync-AdtPickerLevel -ControlName 'DepLvl1' -TopLevel
        Sync-AdtPickerLevel -ControlName 'DepLvl2' -ParentDn (Get-AdtSelectedDn -ControlName 'DepLvl1') -HintControlName 'DepHintText'

        # Créer un utilisateur : les trois niveaux, dans l'ordre.
        Sync-AdtPickerLevel -ControlName 'UserLvl1' -TopLevel
        Sync-AdtPickerLevel -ControlName 'UserLvl2' -ParentDn (Get-AdtSelectedDn -ControlName 'UserLvl1')
        Sync-AdtPickerLevel -ControlName 'UserLvl3' -ParentDn (Get-AdtSelectedDn -ControlName 'UserLvl2') -HintControlName 'UserHintText'
    } finally {
        $script:syncingPickers = $false
    }
}

function Get-AdtSelectedDn {
    # DN de la sélection courante, ou une chaîne vide si rien n'est choisi.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ControlName
    )

    $item = $ui[$ControlName].SelectedItem
    if ($null -eq $item) {
        return ''
    }
    return [string]$item.DistinguishedName
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
    # .ToArray() et non la List elle-même : WPF et PowerShell se renvoient
    # tous deux un tableau, ce qui évite toute conversion de collection.
    $ui['QueueList'].ItemsSource = $script:queue.ToArray()

    $count = $script:queue.Count
    if ($count -eq 0) {
        $ui['QueueCountText'].Text = 'Rien en attente.'
    } else {
        $ui['QueueCountText'].Text = '{0} action(s) en attente.' -f $count
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
    # Reconstruire l'arborescence fait apparaître toute nouvelle OU dans les
    # sélecteurs, marquée « (en attente) ».
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
            ('Identifiant    : {0}' -f $script:archiveUser.SamAccountName)
            ('Nom affiché    : {0}' -f $script:archiveUser.DisplayName)
            ('DN             : {0}' -f $script:archiveUser.DistinguishedName)
            ('État           : {0}' -f $state)
        )
        $ui['ArchiveInfoText'].Text = ($lines -join [Environment]::NewLine)
        Write-AdtStatus -Text ('{0} chargé.' -f $script:archiveUser.SamAccountName)
    } catch {
        Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
        Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
    }
}

# --- Construction de la file -------------------------------------------------
function Add-AdtOuTask {
    # Met en file une seule OU. Un objet = une tâche.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$ParentPath
    )

    $dn = 'OU={0},{1}' -f $Name, $ParentPath
    Add-AdtQueueItem -Item ([pscustomobject]@{
            Kind = 'OU'
            Name = $Name
            ParentPath = $ParentPath
            DistinguishedName = $dn
            Label = 'OU     {0}' -f (Get-AdtDnDisplayPath -DistinguishedName $dn)
        })
    return $dn
}

function Format-AdtPathList {
    # Aplatit une liste de DN en chemins lisibles, un par ligne.
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string[]]$Paths = @()
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($path in $Paths) {
        if ($path) {
            $lines.Add((Get-AdtDnDisplayPath -DistinguishedName $path))
        }
    }
    return [string]($lines -join [Environment]::NewLine)
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
        foreach ($item in $script:queue) {
            if ($item.Kind -ne $kind) {
                continue
            }
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
                $failures.Add(('{0} : {1}' -f $item.Label, $_.Exception.Message))
            }
        }
    }

    $recordPath = $null
    if ($createdUsers.Count -gt 0) {
        # .ToArray() et non @() : @(<List[object]>) lève "Argument types do not match".
        if ($script:recordDirectory) {
            $saved = Save-AdtCredentialRecord -Record $createdUsers.ToArray() -Directory $script:recordDirectory
        } else {
            $saved = Save-AdtCredentialRecord -Record $createdUsers.ToArray()
        }
        $recordPath = [string]$saved.Path
    }

    return [pscustomobject]@{
        Succeeded = $done
        Failed = $failures.Count
        Failures = $failures.ToArray()
        UsersCreated = $createdUsers.Count
        RecordPath = $recordPath
    }
}

# --- Câblage des événements --------------------------------------------------

$ui['NavList'].Add_SelectionChanged({ Sync-AdtPanelVisibility })

# Tout changement de sélecteur resynchronise les trois sections. Le garde-fou
# évite la réentrée pendant la resynchronisation elle-même.
foreach ($pickerName in @('AgLvl1', 'DepLvl1', 'DepLvl2', 'UserLvl1', 'UserLvl2', 'UserLvl3')) {
    $ui[$pickerName].Add_SelectionChanged({
            if ($script:syncingPickers) {
                return
            }
            Sync-AdtPickers
        })
}

# Créer un OU : le parent est toujours la racine du domaine.
$ui['OuAddButton'].Add_Click({
        try {
            $name = $ui['OuNameBox'].Text.Trim()
            if (-not $name) {
                Show-AdtMessage -Text 'Saisissez un nom pour la nouvelle OU.' -Kind 'Warning'
                return
            }
            if (-not $script:rootDn) {
                Show-AdtMessage -Text 'Impossible de déterminer la racine du domaine.' -Kind 'Error'
                return
            }

            $dn = Add-AdtOuTask -Name $name -ParentPath $script:rootDn
            $ui['OuPreviewText'].Text = Get-AdtDnDisplayPath -DistinguishedName $dn
            $ui['OuNameBox'].Text = ''
            Write-AdtStatus -Text '1 OU ajoutée à la file. Vérifiez la file puis cliquez sur Appliquer.' -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Créer une agence
$ui['AgAddButton'].Add_Click({
        try {
            $parentDn = Get-AdtSelectedDn -ControlName 'AgLvl1'
            if (-not $parentDn) {
                Show-AdtMessage -Text 'Choisissez un établissement. S''il n''y en a pas encore, créez-en un dans « Créer un OU ».' -Kind 'Warning'
                return
            }
            $agences = Get-AdtMultilineItems -Text $ui['AgNamesBox'].Text
            if ($agences.Count -eq 0) {
                Show-AdtMessage -Text 'Saisissez au moins un nom d''agence.' -Kind 'Warning'
                return
            }

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($agence in $agences) {
                $queued.Add((Add-AdtOuTask -Name $agence -ParentPath $parentDn))
            }
            $ui['AgPreviewText'].Text = Format-AdtPathList -Paths ([string[]]$queued.ToArray())
            $ui['AgNamesBox'].Text = ''
            Write-AdtStatus -Text ('{0} agence(s) ajoutée(s) à la file. Vérifiez la file puis cliquez sur Appliquer.' -f $queued.Count) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Créer un département
$ui['DepAddButton'].Add_Click({
        try {
            $parentDn = Get-AdtSelectedDn -ControlName 'DepLvl2'
            if (-not $parentDn) {
                Show-AdtMessage -Text 'Choisissez une agence. S''il n''y en a pas encore, créez-en une dans « Créer une agence ».' -Kind 'Warning'
                return
            }
            $departments = Get-AdtMultilineItems -Text $ui['DepNamesBox'].Text
            if ($departments.Count -eq 0) {
                Show-AdtMessage -Text 'Saisissez au moins un nom de département.' -Kind 'Warning'
                return
            }

            $queued = New-Object System.Collections.Generic.List[string]
            foreach ($department in $departments) {
                $queued.Add((Add-AdtOuTask -Name $department -ParentPath $parentDn))
            }
            $ui['DepPreviewText'].Text = Format-AdtPathList -Paths ([string[]]$queued.ToArray())
            $ui['DepNamesBox'].Text = ''
            Write-AdtStatus -Text ('{0} département(s) ajouté(s) à la file. Vérifiez la file puis cliquez sur Appliquer.' -f $queued.Count) -Kind 'Success'
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
            $path = Get-AdtSelectedDn -ControlName 'UserLvl3'
            if (-not $path) {
                Show-AdtMessage -Text 'Choisissez un département. S''il n''y en a pas encore, créez-en un dans « Créer un département ».' -Kind 'Warning'
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
                    Label = 'UTIL   {0} -> {1}   mdp={2}' -f $sam, $displayPath, $script:generatedPassword
                })

            $ui['UserPreviewText'].Text = (
                'Utilisateur ajouté : ' +
                [Environment]::NewLine + ('  Nom complet  : {0} {1}' -f $given, $surname) +
                [Environment]::NewLine + ('  Identifiant  : {0}' -f $sam) +
                [Environment]::NewLine + ('  Département  : {0}' -f $displayPath) +
                [Environment]::NewLine + ('  Mot de passe : {0}' -f $script:generatedPassword) +
                [Environment]::NewLine + '  Changement de mot de passe à la première connexion : non'
            )

            $script:generatedPassword = $null
            $ui['UserPasswordBox'].Text = ''
            $ui['UserGivenBox'].Text = ''
            $ui['UserSurnameBox'].Text = ''
            $ui['UserSamBox'].Text = ''
            Write-AdtStatus -Text ('{0} ajouté à la file. Vérifiez la file puis cliquez sur Appliquer.' -f $sam) -Kind 'Success'
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
                    Label = 'ARCH  {0}' -f $sam
                })
            $ui['ArchivePreviewText'].Text = 'Désactivation de ''{0}'' ajoutée à la file.' -f $sam
            $ui['ArchiveUserBox'].Text = ''
            $ui['ArchiveInfoText'].Text = ''
            $script:archiveUser = $null
            Write-AdtStatus -Text ('Désactivation de {0} ajoutée à la file. Vérifiez la file puis cliquez sur Appliquer.' -f $sam) -Kind 'Success'
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# Contrôles de la file
$ui['QueueRemoveButton'].Add_Click({
        try {
            # Copie dans une List[object] : @(<SelectedItems>) de WPF repasse par
            # une conversion de collection qui peut lever "Argument types do not
            # match". Copier d'abord, puis écrire, évite aussi toute modification
            # de la collection source pendant l'énumération.
            $targets = New-Object System.Collections.Generic.List[object]
            foreach ($item in $ui['QueueList'].SelectedItems) {
                [void]$targets.Add($item)
            }
            if ($targets.Count -eq 0) {
                return
            }
            foreach ($item in $targets) {
                [void]$script:queue.Remove($item)
            }
            Sync-AdtQueue
            Sync-AdtOuTree
            Write-AdtStatus -Text ('{0} action(s) supprimée(s) de la file.' -f $targets.Count)
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
                $summary += ('  {0}' -f $item.Label)
            }
            $body = "Appliquer ces {0} action(s) à l'annuaire ?`n`n{1}" -f $script:queue.Count, ($summary -join [Environment]::NewLine)
            if (-not (Confirm-AdtAction -Text $body -Title 'Appliquer')) {
                return
            }

            $result = Invoke-AdtQueue
            $script:queue.Clear()
            Sync-AdtQueue
            Sync-AdtOuTree

            $lines = @(
                ('Réussies  : {0}' -f $result.Succeeded)
                ('Échouées  : {0}' -f $result.Failed)
            )
            if ($result.UsersCreated -gt 0) {
                $lines += ''
                $lines += ('Fichier de transmission : {0}' -f $result.RecordPath)
                $lines += 'Ce fichier est en clair. Remettez-le à l''utilisateur puis supprimez-le.'
                $lines += 'Ne le commitez jamais et ne le laissez jamais dans le dépôt.'
            }
            if ($result.Failed -gt 0) {
                $lines += ''
                $lines += 'Échecs :'
                foreach ($failure in $result.Failures) {
                    $lines += ('  {0}' -f $failure)
                }
            }

            $icon = [System.Windows.MessageBoxImage]::Information
            if ($result.Failed -gt 0) {
                $icon = [System.Windows.MessageBoxImage]::Warning
            }
            [void][System.Windows.MessageBox]::Show(
                ($lines -join [Environment]::NewLine), 'Appliquer',
                [System.Windows.MessageBoxButton]::OK, $icon)

            if ($result.Failed -gt 0) {
                Write-AdtStatus -Text ('{0} action(s) appliquée(s), {1} en échec.' -f $result.Succeeded, $result.Failed) -Kind 'Error'
            } else {
                Write-AdtStatus -Text ('{0} action(s) appliquée(s).' -f $result.Succeeded) -Kind 'Success'
            }
        } catch {
            Write-AdtStatus -Text $_.Exception.Message -Kind 'Error'
            Show-AdtMessage -Text $_.Exception.Message -Kind 'Error'
        }
    })

# --- Initialisation ----------------------------------------------------------
$ui['NavList'].ItemsSource = @('Créer un OU', 'Créer une agence', 'Créer un département', 'Créer un utilisateur', 'Archiver un utilisateur')
$ui['NavList'].SelectedIndex = 0

try {
    $script:rootDn = [string](Get-AdtDefaultSearchBase)
    $ui['DomainLabel'].Text = 'Domaine : {0}' -f $script:rootDn
    $ui['OuParentText'].Text = $script:rootDn
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
