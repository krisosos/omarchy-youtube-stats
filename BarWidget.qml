import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "krisosos.youtube-stats"

  property bool popupOpen: false
  property bool inSettings: false

  function open() { popupOpen = true }
  function close() { popupOpen = false; inSettings = false }
  function toggle() { popupOpen = !popupOpen; if (!popupOpen) inSettings = false }

  property var stats: ({
    "status": "loading",
    "channel_title": "YouTube",
    "custom_url": "",
    "subscribers": 0,
    "total_views": 0,
    "watch_time_hours": 0.0,
    "period": "28d",
    "selected_metric": "subscribers",
    "lang": "en",
    "avatar_path": "",
    "latest_video": null
  })

  readonly property var i18n: ({
    "en": {
      "set_yt": "Set Up YT",
      "login_yt": "Sign In YT",
      "live_stats": "Live channel stats",
      "step1_msg": "Step 1: Place client_secret.json in ~/.config/omarchy/youtube-stats/",
      "open_folder": "Open Folder",
      "instructions": "Instructions",
      "step2_msg": "Step 2: Connect your Google account (one-time setup)",
      "connect_account": "Connect YouTube Account",
      "subscribers": "Subscribers",
      "views": "Views",
      "watch_time": "Watch Time",
      "latest_video": "Latest Video",
      "no_video": "No uploaded videos found",
      "watch_on_yt": "Watch on YouTube",
      "show_on_bar": "Show on status bar:",
      "period_label": "Watch Time period:",
      "settings": "Settings",
      "back": "Back",
      "days_7": "7 days",
      "days_28": "28 days",
      "days_90": "90 days",
      "days_365": "365 days",
      "refresh": "Refresh",
      "studio": "YouTube Studio"
    },
    "pl": {
      "set_yt": "Ustaw YT",
      "login_yt": "Zaloguj YT",
      "live_stats": "Statystyki kanału na żywo",
      "step1_msg": "Krok 1: Umieść client_secret.json w ~/.config/omarchy/youtube-stats/",
      "open_folder": "Otwórz folder",
      "instructions": "Instrukcja",
      "step2_msg": "Krok 2: Wymagane jednorazowe połączenie z kontem Google",
      "connect_account": "Połącz konto YouTube",
      "subscribers": "Subskrypcje",
      "views": "Wyświetlenia",
      "watch_time": "Watch Time",
      "latest_video": "Ostatni film",
      "no_video": "Brak opublikowanych filmów",
      "watch_on_yt": "Obejrzyj na YouTube",
      "show_on_bar": "Pokaż na pasku zadań:",
      "period_label": "Okres statystyk Watch Time:",
      "settings": "Ustawienia",
      "back": "Wróć",
      "days_7": "7 dni",
      "days_28": "28 dni",
      "days_90": "90 dni",
      "days_365": "365 dni",
      "refresh": "Odśwież",
      "studio": "YouTube Studio"
    }
  })

  function tr(key) {
    var l = (stats && stats.lang === "pl") ? "pl" : "en";
    return (i18n[l] && i18n[l][key]) || (i18n["en"][key]) || key;
  }

  function formatRelativeDate(isoStr) {
    if (!isoStr) return "";
    try {
      var pubDate = new Date(isoStr);
      var now = new Date();
      var diffSec = Math.floor((now - pubDate) / 1000);
      var isPl = (stats && stats.lang === "pl");
      if (diffSec < 3600) {
        var m = Math.max(1, Math.floor(diffSec / 60));
        return isPl ? (m + " min. temu") : (m + "m ago");
      }
      if (diffSec < 86400) {
        var h = Math.floor(diffSec / 3600);
        return isPl ? (h + " godz. temu") : (h + "h ago");
      }
      var d = Math.floor(diffSec / 86400);
      if (d < 30) {
        return isPl ? (d + " dni temu") : (d + "d ago");
      }
      var mo = Math.floor(d / 30);
      if (mo < 12) {
        return isPl ? (mo + " mies. temu") : (mo + "mo ago");
      }
      var y = Math.floor(d / 365);
      return isPl ? (y + " lat temu") : (y + "y ago");
    } catch (e) {
      return "";
    }
  }

  readonly property string pythonScript: Qt.resolvedUrl("scripts/fetch_stats.py").toString().replace(/^file:\/\//, "")
  readonly property string authScript: Qt.resolvedUrl("scripts/auth.py").toString().replace(/^file:\/\//, "")

  function formatShort(num) {
    if (!num || isNaN(num)) return "0";
    if (num >= 1000000) return (num / 1000000).toFixed(1) + "M";
    if (num >= 1000) return (num / 1000).toFixed(1) + "k";
    return num.toString();
  }

  function formatFull(num) {
    if (!num || isNaN(num)) return "0";
    return Number(num).toLocaleString();
  }

  function getBarText() {
    if (!stats) return "YouTube";
    if (stats.status === "needs_client_secret") return tr("set_yt");
    if (stats.status === "auth_required") return tr("login_yt");
    if (stats.status === "loading") return "...";
    var metric = stats.selected_metric || "subscribers";
    if (metric === "subscribers") {
      return formatShort(stats.subscribers);
    } else if (metric === "views") {
      return formatShort(stats.total_views);
    } else if (metric === "watch_time") {
      return (stats.watch_time_hours || 0) + "h";
    }
    return formatShort(stats.subscribers);
  }

  function getBarIcon() {
    var metric = stats ? (stats.selected_metric || "subscribers") : "subscribers";
    if (metric === "watch_time") return "󰔛";
    if (metric === "views") return "󰈈";
    return "󰗃";
  }

  function runFetch(args) {
    if (fetchProc.running) return;
    var cmd = ["python3", root.pythonScript];
    if (args && args.length > 0) {
      cmd = cmd.concat(args);
    }
    fetchProc.command = cmd;
    fetchProc.running = true;
  }

  function setLanguage(newLang) {
    var copy = JSON.parse(JSON.stringify(root.stats));
    copy.lang = newLang;
    root.stats = copy;
    root.runFetch(["--set-lang", newLang]);
  }

  function setMetric(m) {
    var copy = JSON.parse(JSON.stringify(root.stats));
    copy.selected_metric = m;
    root.stats = copy;
    root.runFetch(["--set-metric", m]);
  }

  function setPeriod(p) {
    var copy = JSON.parse(JSON.stringify(root.stats));
    copy.period = p;
    root.stats = copy;
    root.runFetch(["--set-period", p]);
  }

  function startAuth() {
    if (root.bar) {
      root.bar.run("alacritty -e python3 " + root.authScript);
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: fetchProc
    command: ["python3", root.pythonScript]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim();
        if (!raw) return;
        try {
          var parsed = JSON.parse(raw);
          root.stats = parsed;
        } catch (e) {
          console.log("[youtube-stats] Parse error: " + e);
        }
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: 900000 // 15 minut
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runFetch([])
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.getBarIcon() + " " + root.getBarText()
    labelVisible: !root.vertical
    tooltipText: "YouTube: " + (root.stats.channel_title || "YouTube Stats for Creators")
    onPressed: function(mouseButton) {
      root.toggle();
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen

    onOpenChanged: {
      if (open !== root.popupOpen) {
        root.popupOpen = open;
      }
    }

    contentWidth: popup.fittedContentWidth(Style.space(360))
    contentHeight: popup.fittedContentHeight(mainCol.implicitHeight)

    Column {
      id: mainCol
      width: parent.width
      spacing: Style.space(12)

      // 1. Nagłówek profilu + kontrolki (EN / PL + Zębatka ustawień)
      Row {
        width: parent.width
        spacing: Style.space(10)

        Rectangle {
          width: Style.space(44)
          height: Style.space(44)
          radius: Style.space(22)
          color: Color.accent
          clip: true

          Image {
            id: avatarImg
            anchors.fill: parent
            source: (root.stats && root.stats.avatar_path) ? ("file://" + root.stats.avatar_path) : ""
            fillMode: Image.PreserveAspectCrop
            visible: status === Image.Ready
          }

          Text {
            anchors.centerIn: parent
            visible: !avatarImg.visible
            text: "󰗃"
            font.family: Style.font.family
            font.pixelSize: Style.font.display
            color: Color.background
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(44 + 10 + 10) - topControls.implicitWidth
          spacing: Style.space(2)

          Text {
            text: root.inSettings ? root.tr("settings") : (root.stats.channel_title || "YouTube Stats for Creators")
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
            color: Color.foreground
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.inSettings ? (root.stats.channel_title || "@krisosos_") : (root.stats.custom_url || root.tr("live_stats"))
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
            elide: Text.ElideRight
            width: parent.width
          }
        }

        Row {
          id: topControls
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Button {
            text: "EN"
            selected: (!root.stats || root.stats.lang !== "pl")
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            onClicked: root.setLanguage("en")
          }

          Button {
            text: "PL"
            selected: (root.stats && root.stats.lang === "pl")
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            onClicked: root.setLanguage("pl")
          }

          Button {
            iconText: "󰒓"
            selected: root.inSettings
            horizontalPadding: Style.space(7)
            verticalPadding: Style.space(4)
            onClicked: root.inSettings = !root.inSettings
          }
        }
      }

      // Komunikat o braku pliku client_secret.json
      Rectangle {
        width: parent.width
        height: secretCol.implicitHeight + Style.space(16)
        visible: root.stats.status === "needs_client_secret"
        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)
        radius: Style.space(8)
        border.color: Color.urgent
        border.width: 1

        Column {
          id: secretCol
          anchors.centerIn: parent
          width: parent.width - Style.space(20)
          spacing: Style.space(8)

          Text {
            text: root.tr("step1_msg")
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            color: Color.urgent
            wrapMode: Text.Wrap
            width: parent.width
          }

          Row {
            spacing: Style.space(6)

            Button {
              text: root.tr("open_folder")
              iconText: "󰉋"
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              onClicked: Qt.openUrlExternally("file://" + Quickshell.env("HOME") + "/.config/omarchy/youtube-stats")
            }

            Button {
              text: root.tr("instructions")
              iconText: "󰋽"
              horizontalPadding: Style.space(10)
              verticalPadding: Style.space(6)
              onClicked: Qt.openUrlExternally("https://github.com/krisosos/omarchy-youtube-stats#readme")
            }
          }
        }
      }

      // Komunikat o braku autoryzacji
      Rectangle {
        width: parent.width
        height: authCol.implicitHeight + Style.space(16)
        visible: root.stats.status === "auth_required"
        color: Qt.rgba(Color.urgent.r, Color.urgent.g, Color.urgent.b, 0.15)
        radius: Style.space(8)
        border.color: Color.urgent
        border.width: 1

        Column {
          id: authCol
          anchors.centerIn: parent
          width: parent.width - Style.space(20)
          spacing: Style.space(8)

          Text {
            text: root.tr("step2_msg")
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            color: Color.urgent
            wrapMode: Text.Wrap
            width: parent.width
          }

          Button {
            text: root.tr("connect_account")
            iconText: "󰌹"
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(6)
            onClicked: root.startAuth()
          }
        }
      }

      // ==========================================
      // === WIDOK USTAWIEŃ (gdy root.inSettings) ==
      // ==========================================
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: root.inSettings

        // Wybór wskaźnika na pasku
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: root.tr("show_on_bar")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: root.tr("subscribers")
              iconText: "󰚥"
              selected: root.stats.selected_metric === "subscribers"
              onClicked: root.setMetric("subscribers")
            }

            Button {
              text: root.tr("views")
              iconText: "󰈈"
              selected: root.stats.selected_metric === "views"
              onClicked: root.setMetric("views")
            }

            Button {
              text: root.tr("watch_time")
              iconText: "󰔛"
              selected: root.stats.selected_metric === "watch_time"
              onClicked: root.setMetric("watch_time")
            }
          }
        }

        // Zakres czasu dla Watch Time
        Column {
          width: parent.width
          spacing: Style.space(6)

          Text {
            text: root.tr("period_label")
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Color.muted
          }

          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              text: root.tr("days_7")
              selected: root.stats.period === "7d"
              onClicked: root.setPeriod("7d")
            }

            Button {
              text: root.tr("days_28")
              selected: root.stats.period === "28d"
              onClicked: root.setPeriod("28d")
            }

            Button {
              text: root.tr("days_90")
              selected: root.stats.period === "90d"
              onClicked: root.setPeriod("90d")
            }

            Button {
              text: root.tr("days_365")
              selected: root.stats.period === "365d"
              onClicked: root.setPeriod("365d")
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // Dodatkowe opcje i powrót
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: root.tr("back")
            iconText: "󰁍"
            horizontalPadding: Style.space(12)
            verticalPadding: Style.space(6)
            onClicked: root.inSettings = false
          }

          Button {
            text: root.tr("open_folder")
            iconText: "󰉋"
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(6)
            onClicked: Qt.openUrlExternally("file://" + Quickshell.env("HOME") + "/.config/omarchy/youtube-stats")
          }

          Button {
            text: root.tr("instructions")
            iconText: "󰋽"
            horizontalPadding: Style.space(10)
            verticalPadding: Style.space(6)
            onClicked: Qt.openUrlExternally("https://github.com/krisosos/omarchy-youtube-stats#readme")
          }
        }
      }

      // ===============================================
      // === GŁÓWNY WIDOK STATYSTYK (!root.inSettings) ==
      // ===============================================
      Column {
        width: parent.width
        spacing: Style.space(12)
        visible: !root.inSettings

        // 2. Kafelki ze statystykami (3 kafelki)
        Row {
          width: parent.width
          spacing: Style.space(6)

          // Subskrypcje
          Rectangle {
            width: (parent.width - Style.space(12)) / 3
            height: Style.space(68)
            radius: Style.space(8)
            color: root.stats.selected_metric === "subscribers" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
            border.color: root.stats.selected_metric === "subscribers" ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
            border.width: 1

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Text {
                text: "󰚥 " + root.tr("subscribers")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.formatFull(root.stats.subscribers)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: Color.foreground
                elide: Text.ElideRight
                width: parent.width
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMetric("subscribers")
            }
          }

          // Wyświetlenia
          Rectangle {
            width: (parent.width - Style.space(12)) / 3
            height: Style.space(68)
            radius: Style.space(8)
            color: root.stats.selected_metric === "views" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
            border.color: root.stats.selected_metric === "views" ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
            border.width: 1

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Text {
                text: "󰈈 " + root.tr("views")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.formatShort(root.stats.total_views)
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: Color.foreground
                elide: Text.ElideRight
                width: parent.width
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMetric("views")
            }
          }

          // Watch Time
          Rectangle {
            width: (parent.width - Style.space(12)) / 3
            height: Style.space(68)
            radius: Style.space(8)
            color: root.stats.selected_metric === "watch_time" ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.2) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.06)
            border.color: root.stats.selected_metric === "watch_time" ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
            border.width: 1

            Column {
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(4)

              Text {
                text: "󰔛 " + root.tr("watch_time")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                color: Color.muted
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: (root.stats.watch_time_hours || 0) + "h"
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
                color: Color.foreground
                elide: Text.ElideRight
                width: parent.width
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: root.setMetric("watch_time")
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // 3. Sekcja: Ostatni film (Latest Video)
        Column {
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Math.max(rankBadge.height, dateText.implicitHeight)

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰗃 " + root.tr("latest_video")
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                font.bold: true
                color: Color.foreground
              }

              // Badge z rankingiem Studio (np. 🏆 1 / 10 lub 🏆 6 / 10)
              Rectangle {
                id: rankBadge
                anchors.verticalCenter: parent.verticalCenter
                visible: !!(root.stats && root.stats.latest_video && root.stats.latest_video.rank)
                readonly property int vRank: (root.stats && root.stats.latest_video) ? (root.stats.latest_video.rank || 0) : 0
                readonly property int vTotal: (root.stats && root.stats.latest_video) ? (root.stats.latest_video.rank_total || 10) : 10
                width: rankText.implicitWidth + Style.space(12)
                height: Style.space(20)
                radius: Style.space(10)
                color: (vRank === 1) ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.08)
                border.color: (vRank === 1) ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.2)
                border.width: 1

                Text {
                  id: rankText
                  anchors.centerIn: parent
                  text: "🏆 " + rankBadge.vRank + " / " + rankBadge.vTotal
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: rankBadge.vRank === 1
                  color: (rankBadge.vRank === 1) ? Color.accent : Color.foreground
                }
              }
            }

            Text {
              id: dateText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: (root.stats && root.stats.latest_video && root.stats.latest_video.published_at) ? root.formatRelativeDate(root.stats.latest_video.published_at) : ""
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              color: Color.muted
            }
          }

          // Karta ostatniego filmu
          Rectangle {
            width: parent.width
            height: Style.space(76)
            radius: Style.space(8)
            color: videoMouseArea.containsMouse ? Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.12) : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.05)
            border.color: videoMouseArea.containsMouse ? Color.accent : Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.15)
            border.width: 1
            clip: true

            Row {
              anchors.fill: parent
              anchors.margins: Style.space(6)
              spacing: Style.space(10)

              // Miniatura
              Rectangle {
                width: Style.space(114)
                height: Style.space(64)
                radius: Style.space(6)
                color: Color.background
                clip: true

                Image {
                  id: videoThumb
                  anchors.fill: parent
                  source: (root.stats && root.stats.latest_video && root.stats.latest_video.thumbnail_path) ? ("file://" + root.stats.latest_video.thumbnail_path) : ""
                  fillMode: Image.PreserveAspectCrop
                  visible: status === Image.Ready
                }

                Rectangle {
                  anchors.centerIn: parent
                  width: Style.space(26)
                  height: Style.space(26)
                  radius: Style.space(13)
                  color: Qt.rgba(0, 0, 0, 0.6)
                  visible: videoThumb.visible

                  Text {
                    anchors.centerIn: parent
                    text: "󰐊"
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: "#ffffff"
                  }
                }

                Text {
                  anchors.centerIn: parent
                  visible: !videoThumb.visible
                  text: "󰗃"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  color: Color.muted
                }
              }

              // Informacje: Tytuł + Statystyki (wyświetlenia, lajki, komentarze)
              Column {
                width: parent.width - Style.space(114 + 10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(4)

                Text {
                  text: (root.stats && root.stats.latest_video && root.stats.latest_video.title) ? root.stats.latest_video.title : root.tr("no_video")
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  color: Color.foreground
                  width: parent.width
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                }

                Row {
                  spacing: Style.space(10)
                  visible: !!(root.stats && root.stats.latest_video)

                  Text {
                    text: "󰈈 " + root.formatShort(root.stats.latest_video ? root.stats.latest_video.views : 0)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }

                  Text {
                    text: "󰋑 " + root.formatShort(root.stats.latest_video ? root.stats.latest_video.likes : 0)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }

                  Text {
                    text: "󰆈 " + root.formatShort(root.stats.latest_video ? root.stats.latest_video.comments : 0)
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                    color: Color.muted
                  }
                }
              }
            }

            MouseArea {
              id: videoMouseArea
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              hoverEnabled: true
              onClicked: {
                if (root.stats && root.stats.latest_video && root.stats.latest_video.id) {
                  Qt.openUrlExternally("https://youtu.be/" + root.stats.latest_video.id);
                }
              }
            }
          }
        }

        PanelSeparator {
          width: parent.width
        }

        // 4. Dolne przyciski
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: root.tr("refresh")
            iconText: "󰑐"
            onClicked: root.runFetch([])
          }

          Button {
            text: root.tr("studio")
            iconText: "󰄠"
            onClicked: Qt.openUrlExternally("https://studio.youtube.com")
          }
        }
      }
    }
  }
}
