##Change Teams Island mode to Teams Only##
##Teams Powershell module installeren##
Install-Module -Name MicrosoftTeams

#Verbinden naar Tenant#
Connect-MicrosoftTeams

##verander user1@example.com met de echte gebruikersnaam##
Grant-CsTeamsUpgradePolicy -PolicyName UpgradeToTeams -Identity user1@example.com

##voor alle gebruikers binnen een tennant
##Grant-CsTeamsUpgradePolicy -PolicyName UpgradeToTeams -Global##