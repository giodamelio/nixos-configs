import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0
  property var pluginApi: null

  // Usage data
  property real fiveHourUtil: 0
  property real sevenDayUtil: 0
  property var fiveHourResetAt: null
  property var sevenDayResetAt: null
  property real sevenDayOpusUtil: -1
  property real sevenDaySonnetUtil: -1
  property var lastFetchedTime: null
  property bool hasError: false
  property string errorMessage: ""

  // Sizing (matching SystemMonitor compact pattern)
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screen ? screen.name : "")
  readonly property real iconSize: Style.toOdd(capsuleHeight * 0.48)
  readonly property real miniGaugeWidth: Math.max(3, Style.toOdd(iconSize * 0.25))

  readonly property real contentWidth: Math.round(mainLayout.implicitWidth + Style.margin2M)
  readonly property real contentHeight: capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  // Color based on utilization level
  function utilizationColor(util) {
    if (util >= 80) return Color.mError;
    if (util >= 60) return Color.mTertiary;
    return Color.mPrimary;
  }

  // Format a future date as "in Xh Ym"
  function formatTimeUntil(date) {
    if (!date) return "";
    var seconds = Math.floor((date - Time.now) / 1000);
    if (seconds <= 0) return "now";
    return "in " + Time.formatVagueHumanReadableDuration(seconds);
  }

  // Read credentials from Claude Code
  FileView {
    id: credsFile
    path: Quickshell.env("HOME") + "/.claude/.credentials.json"
    watchChanges: true
    printErrors: false

    onLoaded: {
      try {
        var data = JSON.parse(text());
        if (data.claudeAiOauth && data.claudeAiOauth.accessToken) {
          root.fetchUsage(data.claudeAiOauth.accessToken);
        } else {
          root.hasError = true;
          root.errorMessage = "No OAuth token in credentials";
        }
      } catch (e) {
        root.hasError = true;
        root.errorMessage = "Failed to parse credentials: " + e;
      }
    }

    onLoadFailed: function (error) {
      root.hasError = true;
      root.errorMessage = "Credentials not found";
    }
  }

  // Fetch usage data from API
  function fetchUsage(token) {
    var xhr = new XMLHttpRequest();
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE) {
        if (xhr.status === 200) {
          try {
            var data = JSON.parse(xhr.responseText);
            root.fiveHourUtil = data.five_hour.utilization;
            root.sevenDayUtil = data.seven_day.utilization;
            root.fiveHourResetAt = data.five_hour.resets_at ? new Date(data.five_hour.resets_at) : null;
            root.sevenDayResetAt = data.seven_day.resets_at ? new Date(data.seven_day.resets_at) : null;

            if (data.seven_day_opus)
              root.sevenDayOpusUtil = data.seven_day_opus.utilization;
            if (data.seven_day_sonnet)
              root.sevenDaySonnetUtil = data.seven_day_sonnet.utilization;

            root.lastFetchedTime = new Date();
            root.hasError = false;
            root.errorMessage = "";
          } catch (e) {
            root.hasError = true;
            root.errorMessage = "Failed to parse response";
          }
        } else {
          root.hasError = true;
          root.errorMessage = "API error: " + xhr.status;
        }
      }
    };

    xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
    xhr.setRequestHeader("Authorization", "Bearer " + token);
    xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
    xhr.setRequestHeader("User-Agent", "noctalia-claude-usage/1.0.0");
    xhr.send();
  }

  // Poll timer - refresh every 5 minutes
  Timer {
    id: refreshTimer
    interval: 300000
    repeat: true
    running: true
    onTriggered: credsFile.reload()
  }

  // Initial fetch on load
  Component.onCompleted: credsFile.reload()

  // Hover popup
  MouseArea {
    id: tooltipArea
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.NoButton

    onEntered: usagePopup.visible = true
    onExited: usagePopup.visible = false
  }

  PopupWindow {
    id: usagePopup
    visible: false
    color: "transparent"
    anchor.item: root
    anchor.rect.x: (root.width - implicitWidth) / 2
    anchor.rect.y: {
      var dir = BarService.getTooltipDirection(root.screen?.name);
      if (dir === "top") return -implicitHeight - Style.marginXS;
      return root.height + Style.marginXS;
    }

    implicitWidth: popupContent.implicitWidth + Style.marginM * 2
    implicitHeight: popupContent.implicitHeight + Style.marginM * 2

    Rectangle {
      anchors.fill: parent
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: Style.borderS
      radius: Style.radiusS

      ColumnLayout {
        id: popupContent
        anchors.fill: parent
        anchors.margins: Style.marginM
        spacing: Style.marginXS

        GridLayout {
          columns: 4
          columnSpacing: Style.marginS
          rowSpacing: Style.marginXS

          // 5-hour row
          NText { text: "5-hour"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
          NLinearGauge {
            ratio: root.fiveHourUtil / 100; orientation: Qt.Horizontal
            fillColor: utilizationColor(root.fiveHourUtil)
            Layout.preferredWidth: 120; Layout.preferredHeight: 8
          }
          NText { text: Math.round(root.fiveHourUtil) + "%"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignRight }
          NText { text: { if (usagePopup.visible) void Time.timestamp; return root.fiveHourResetAt ? formatTimeUntil(root.fiveHourResetAt) : ""; } pointSize: Style.fontSizeXS; color: Color.mOutline; horizontalAlignment: Text.AlignRight }

          // 7-day row
          NText { text: "7-day"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
          NLinearGauge {
            ratio: root.sevenDayUtil / 100; orientation: Qt.Horizontal
            fillColor: utilizationColor(root.sevenDayUtil)
            Layout.preferredWidth: 120; Layout.preferredHeight: 8
          }
          NText { text: Math.round(root.sevenDayUtil) + "%"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignRight }
          NText { text: { if (usagePopup.visible) void Time.timestamp; return root.sevenDayResetAt ? formatTimeUntil(root.sevenDayResetAt) : ""; } pointSize: Style.fontSizeXS; color: Color.mOutline; horizontalAlignment: Text.AlignRight }

          // Opus row
          NText { visible: root.sevenDayOpusUtil >= 0; text: "Opus"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
          NLinearGauge {
            visible: root.sevenDayOpusUtil >= 0
            ratio: root.sevenDayOpusUtil / 100; orientation: Qt.Horizontal
            fillColor: utilizationColor(root.sevenDayOpusUtil)
            Layout.preferredWidth: 120; Layout.preferredHeight: 8
          }
          NText { visible: root.sevenDayOpusUtil >= 0; text: Math.round(root.sevenDayOpusUtil) + "%"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignRight }
          NText { visible: root.sevenDayOpusUtil >= 0; text: ""; pointSize: Style.fontSizeXS; color: Color.mOutline }

          // Sonnet row
          NText { visible: root.sevenDaySonnetUtil >= 0; text: "Sonnet"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant }
          NLinearGauge {
            visible: root.sevenDaySonnetUtil >= 0
            ratio: root.sevenDaySonnetUtil / 100; orientation: Qt.Horizontal
            fillColor: utilizationColor(root.sevenDaySonnetUtil)
            Layout.preferredWidth: 120; Layout.preferredHeight: 8
          }
          NText { visible: root.sevenDaySonnetUtil >= 0; text: Math.round(root.sevenDaySonnetUtil) + "%"; pointSize: Style.fontSizeS; color: Color.mOnSurfaceVariant; horizontalAlignment: Text.AlignRight }
          NText { visible: root.sevenDaySonnetUtil >= 0; text: ""; pointSize: Style.fontSizeXS; color: Color.mOutline }
        }

        // Footer: error + last fetched
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            visible: root.hasError
            text: root.errorMessage
            pointSize: Style.fontSizeXS
            color: Color.mError
          }

          Item { Layout.fillWidth: true }

          NText {
            visible: root.lastFetchedTime !== null
            // Reference Time.timestamp to trigger re-evaluation every second
            text: { if (usagePopup.visible) void Time.timestamp; return "Fetched " + Time.formatRelativeTime(root.lastFetchedTime); }
            pointSize: Style.fontSizeXS
            color: Color.mOutline
          }
        }
      }
    }
  }

  // Visual capsule
  Rectangle {
    id: visualCapsule
    width: root.contentWidth
    height: root.contentHeight
    anchors.centerIn: parent
    radius: Style.radiusM
    color: Style.capsuleColor
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    RowLayout {
      id: mainLayout
      anchors.centerIn: parent
      spacing: 3

      // Claude icon
      Item {
        Layout.preferredWidth: iconSize
        Layout.preferredHeight: capsuleHeight
        Layout.alignment: Qt.AlignVCenter

        IconImage {
          width: iconSize
          height: iconSize
          anchors.centerIn: parent
          source: "file://" + (root.pluginApi ? root.pluginApi.pluginDir : ".") + "/claude-icon.svg"
          smooth: true
          asynchronous: true
          layer.enabled: true
          layer.effect: ShaderEffect {
            property color targetColor: root.hasError ? Color.mError : Color.mPrimary
            property real colorizeMode: 2.0
            fragmentShader: Qt.resolvedUrl(Quickshell.shellDir + "/Shaders/qsb/appicon_colorize.frag.qsb")
          }
        }
      }

      // 5-hour gauge
      NLinearGauge {
        ratio: root.fiveHourUtil / 100
        orientation: Qt.Vertical
        fillColor: utilizationColor(root.fiveHourUtil)
        width: miniGaugeWidth
        height: iconSize
        Layout.alignment: Qt.AlignVCenter
      }

      // 7-day gauge
      NLinearGauge {
        ratio: root.sevenDayUtil / 100
        orientation: Qt.Vertical
        fillColor: utilizationColor(root.sevenDayUtil)
        width: miniGaugeWidth
        height: iconSize
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }
}
