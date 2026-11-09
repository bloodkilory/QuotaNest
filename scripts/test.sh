#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SWIFT_COMPILER=(swiftc -whole-module-optimization)
mkdir -p .build/localizations.bundle
cp -R Resources/*.lproj .build/localizations.bundle/
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Tests/main.swift -o .build/model-tests
.build/model-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Tests/Protocol/main.swift -o .build/protocol-tests
.build/protocol-tests
"${SWIFT_COMPILER[@]}" -swift-version 5 Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Sources/ProviderPayload.swift Sources/OfficialProviders.swift Sources/ClaudeDesktopCredentials.swift Tests/Claude/main.swift -o .build/claude-tests
.build/claude-tests
"${SWIFT_COMPILER[@]}" -swift-version 5 Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/CodexClient.swift Sources/ClaudeDesktopCredentials.swift Tests/ClaudeDesktop/CredentialData.swift Tests/ClaudeDesktop/main.swift -o .build/desktop-credential-tests
.build/desktop-credential-tests
"${SWIFT_COMPILER[@]}" -swift-version 5 Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Sources/ProviderPayload.swift Sources/OfficialProviders.swift Sources/ClaudeDesktopCredentials.swift Tests/ClaudeDesktop/CredentialData.swift Tests/ClaudeDesktopClient/main.swift -o .build/desktop-source-tests
.build/desktop-source-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/ProviderState.swift Sources/ProviderPayload.swift Tests/Providers/main.swift -o .build/provider-tests
.build/provider-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 Sources/CCSwitchStore.swift Sources/DeepSeekBalance.swift Sources/DeepSeekBalanceClient.swift Sources/ConnectedAccountState.swift Tests/ConnectedAccounts/main.swift -o .build/connected-account-tests
.build/connected-account-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 Sources/QuotaModels.swift Sources/CodexClient.swift Sources/BoundedCommand.swift Tests/Command/main.swift -o .build/command-tests
.build/command-tests

"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/ProviderState.swift Sources/ProviderMark.swift Sources/GlassAppearance.swift Sources/CapsuleView.swift Tests/Capsule/main.swift -o .build/capsule-tests
.build/capsule-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 -framework AppKit Sources/CCSwitchStore.swift Sources/DeepSeekBalance.swift Sources/DeepSeekBalanceClient.swift Sources/ConnectedAccountState.swift Sources/GlassAppearance.swift Sources/ProviderState.swift Sources/QuotaModels.swift Sources/DisplaySource.swift Sources/ConnectedAccountsView.swift Tests/ConnectedUI/main.swift -o .build/connected-ui-tests
.build/connected-ui-tests


"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/ProviderState.swift Sources/CodexClient.swift Sources/ProviderPayload.swift Sources/ChinaLoginPayload.swift Sources/ChinaLoginClients.swift Tests/ChinaLogin/main.swift -o .build/china-login-tests
.build/china-login-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 Sources/UpdateModels.swift Sources/ReleaseUpdateClient.swift Sources/UpdateHelperContract.swift Sources/UpdateReplacement.swift Sources/UpdateInstaller.swift Sources/UpdatePrivilegeLauncher.swift Sources/LoginItemManager.swift Sources/CodexClient.swift Sources/QuotaModels.swift Tests/Updates/main.swift -o .build/update-tests
.build/update-tests
"${SWIFT_COMPILER[@]}" Sources/Localization.swift Tests/Support.swift -swift-version 5 Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/UpdateReplacement.swift Helpers/Update/main.swift -o .build/update-helper-tests
if .build/update-helper-tests --request /unapproved/request.json; then
    echo 'FAIL helper accepted invalid request'; exit 1
fi
"${SWIFT_COMPILER[@]}" -swift-version 5 Sources/Localization.swift Sources/QuotaModels.swift Sources/ProviderState.swift Sources/DisplaySource.swift Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/CCSwitchStore.swift Sources/DeepSeekBalance.swift Sources/DeepSeekBalanceClient.swift Sources/ConnectedAccountState.swift Tests/Localization/main.swift -o .build/localization-tests
.build/localization-tests
"${SWIFT_COMPILER[@]}" -swift-version 5 -framework AppKit Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/ProviderState.swift Sources/DisplaySource.swift Sources/CCSwitchStore.swift Sources/DeepSeekBalance.swift Sources/DeepSeekBalanceClient.swift Sources/ConnectedAccountState.swift Sources/GlassAppearance.swift Sources/ConnectedAccountsView.swift Sources/GlassPopover.swift Sources/OfficialQuotaView.swift Sources/UpdateModels.swift Sources/UpdateHelperContract.swift Sources/SettingsView.swift Tests/LocalizationUI/main.swift -o .build/localization-ui-tests
.build/localization-ui-tests
"${SWIFT_COMPILER[@]}" -swift-version 5 Sources/Localization.swift Tests/Support.swift Sources/QuotaModels.swift Sources/CodexClient.swift Sources/ProviderState.swift Sources/DisplaySource.swift Sources/ProviderPayload.swift Sources/ChinaLoginPayload.swift Sources/ChinaLoginClients.swift Sources/BoundedCommand.swift Sources/CCSwitchStore.swift Sources/DeepSeekBalance.swift Sources/DeepSeekBalanceClient.swift Sources/HarnessBalanceClient.swift Tests/Harness/main.swift -o .build/harness-tests
.build/harness-tests
