/*
 * Focus Swap Monitor
 *
 * The active normal window belongs on the local panel; the previously active
 * normal window belongs on the low-latency-cost VNC panel.  Activating a
 * window on that VNC panel therefore exchanges it with the previous window.
 */

const LOCAL_OUTPUT_NAME = "eDP-1";
const REMOTE_OUTPUT_NAME = "Virtual-Chromebook";

let previousWindow = null;
let reportedMissingOutputs = false;

function outputNamed(name) {
    const screens = workspace.screens;
    for (let i = 0; i < screens.length; ++i) {
        if (screens[i].name === name) {
            return screens[i];
        }
    }
    return null;
}

function isEligible(window) {
    return window !== null &&
        window !== undefined &&
        window.managed &&
        !window.deleted &&
        window.normalWindow &&
        !window.minimized &&
        !window.keepAbove &&
        occupiesItsWorkArea(window);
}

function occupiesItsWorkArea(window) {
    if (window.fullScreen) {
        return true;
    }

    // KWin exposes the actual usable maximized area, which correctly accounts
    // for a panel and for different sizes of the local and virtual outputs.
    const area = workspace.clientArea(KWin.MaximizeArea, window);
    const frame = window.frameGeometry;
    const tolerance = 2;
    return Math.abs(frame.x - area.x) <= tolerance &&
        Math.abs(frame.y - area.y) <= tolerance &&
        Math.abs(frame.width - area.width) <= tolerance &&
        Math.abs(frame.height - area.height) <= tolerance;
}

function moveTo(window, output) {
    if (isEligible(window) && window.output !== output) {
        workspace.sendClientToScreen(window, output);
    }
}

function handleActivation(window) {
    // Dialogs, menus, panels, task switchers, etc. must not disturb the pair.
    if (!isEligible(window)) {
        return;
    }

    const localOutput = outputNamed(LOCAL_OUTPUT_NAME);
    const remoteOutput = outputNamed(REMOTE_OUTPUT_NAME);
    if (localOutput === null || remoteOutput === null) {
        if (!reportedMissingOutputs) {
            print("Focus Swap Monitor: waiting for " + LOCAL_OUTPUT_NAME +
                  " and " + REMOTE_OUTPUT_NAME + ".");
            reportedMissingOutputs = true;
        }
        previousWindow = window;
        return;
    }
    reportedMissingOutputs = false;

    if (window === previousWindow) {
        return;
    }

    // Put the selected window under the local pointer/keyboard first, then
    // send the window it displaced to the VNC-only output.
    moveTo(window, localOutput);
    moveTo(previousWindow, remoteOutput);
    previousWindow = window;
}

workspace.windowActivated.connect(handleActivation);

// Do not rearrange anything when the script is enabled; begin with the
// currently focused app as the incumbent and swap on the next app activation.
if (isEligible(workspace.activeWindow)) {
    previousWindow = workspace.activeWindow;
}

// An output can disappear while the laptop is docked/undocked. Resetting the
// pair makes the first later activation a safe baseline rather than moving a
// stale window to an unrelated newly attached display.
workspace.screensChanged.connect(function () {
    previousWindow = isEligible(workspace.activeWindow) ? workspace.activeWindow : null;
    reportedMissingOutputs = false;
});
