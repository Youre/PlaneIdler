using PlaneIdler.Systems;
using PlaneIdler.Sim;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
using UnityEngine.EventSystems;
#if ENABLE_INPUT_SYSTEM
using UnityEngine.InputSystem.UI;
#endif

namespace PlaneIdler.UI
{
    /// <summary>
    /// HUD that mirrors the Godot layout: bank/time-scale top-right, status small at top-center,
    /// time controls under top bar, console bottom-left, clock bottom-left, income/traffic charts bottom-right,
    /// upgrades list and build queue on the right.
    /// </summary>
    public class HudRuntimeBuilder : MonoBehaviour
    {
        [SerializeField] private SimState simState;
        [SerializeField] private UpgradeManager upgradeManager;
        [SerializeField] private CatalogLoader catalog;
        [SerializeField] private SimController simController;
        [SerializeField] private PlaneIdler.Airport.StandManager standManager;
        [SerializeField] private PlaneIdler.Airport.Runway runway;

        private TMP_Text _bank;
        private TMP_Text _clock;
        private TMP_Text _status;
        private ConsoleLogSink _console;
        private TMP_Text _consoleText;
        private IncomeBarChart _incomeChart;
        private StackedBarChart _trafficChart;
        private RectTransform _upgradesContent;
        private RectTransform _buildContent;

        private float _chartTimer;
        private float _statusTimer;

        private void Awake()
        {
            simState ??= Resources.Load<SimState>("Settings/SimState");
            upgradeManager ??= FindFirstObjectByType<UpgradeManager>();
            catalog ??= FindFirstObjectByType<CatalogLoader>();
            simController ??= FindFirstObjectByType<SimController>();
            standManager ??= FindFirstObjectByType<PlaneIdler.Airport.StandManager>();
            runway ??= FindFirstObjectByType<PlaneIdler.Airport.Runway>();

            EnsureEventSystem();
            BuildCanvas();
            RefreshUpgrades();
            RefreshBuildQueue();
            UpdateBankLabel();
            if (_status != null) _status.text = BuildStatus();
        }

        private void Start()
        {
            // Ensure we share the same SimState instance as the SimController,
            // so bank and daily buckets stay in sync.
            if (simController == null)
                simController = FindFirstObjectByType<SimController>();
            if (simController != null)
                simState = simController.State;
        }

        private void OnEnable()
        {
            Events.BankChanged += OnBank;
            Events.TimeScaleChanged += OnTimeScale;
            Events.ConstructionUpdated += OnConstructionUpdated;
        }

        private void OnDisable()
        {
            Events.BankChanged -= OnBank;
            Events.TimeScaleChanged -= OnTimeScale;
            Events.ConstructionUpdated -= OnConstructionUpdated;
        }

        private void BuildCanvas()
        {
            var canvasGo = new GameObject("HUD_Canvas");
            canvasGo.layer = LayerMask.NameToLayer("UI");
            var canvas = canvasGo.AddComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            var scaler = canvasGo.AddComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920, 1080);
            scaler.matchWidthOrHeight = 0.5f;
            canvasGo.AddComponent<GraphicRaycaster>();

            // Status top-center (with shadow)
            _status = MakeLabel(canvasGo.transform, "Rwy: -- | Stands --/--", 24,
                pos: new Vector2(0, -14), anchor: new Vector2(0.5f, 1f), pivot: new Vector2(0.5f, 1f), color: Color.white, shadow: true);
            _status.alignment = TextAlignmentOptions.Center;

            // Bank/time-scale top-right
            var bankPanel = CreatePanel(canvasGo.transform, new Vector2(-16, -16), new Vector2(280, 64),
                anchorMin: new Vector2(1, 1), anchorMax: new Vector2(1, 1), pivotOverride: new Vector2(1, 1));
            _bank = MakeLabel(bankPanel, "Bank: 0", 24, new Vector2(-12, -12), anchor: new Vector2(1, 1), pivot: new Vector2(1, 1), color: Color.white);
            _bank.alignment = TextAlignmentOptions.Right;

            // Time controls top-right under bank
            var timePanel = CreatePanel(canvasGo.transform, new Vector2(-16, -90), new Vector2(520, 50),
                anchorMin: new Vector2(1, 1), anchorMax: new Vector2(1, 1), pivotOverride: new Vector2(1, 1));
            var hlg = timePanel.gameObject.AddComponent<HorizontalLayoutGroup>();
            hlg.padding = new RectOffset(6, 6, 6, 6);
            hlg.spacing = 6f;
            hlg.childForceExpandHeight = false;
            hlg.childForceExpandWidth = false;
            float[] speeds = { 0.5f, 1, 2, 4, 8, 16, 32, 64 };
            foreach (var s in speeds)
            {
                var btn = CreateButton(timePanel, $"x{s}", new Vector2(58, 34));
                float sp = s;
                btn.onClick.AddListener(() => SetTimeScale(sp));
            }

            // Console bottom-left (scrollable)
            var consolePanel = CreatePanel(canvasGo.transform, new Vector2(16, 96), new Vector2(720, 240),
                anchorMin: new Vector2(0, 0), anchorMax: new Vector2(0, 0), pivotOverride: new Vector2(0, 0));
            var consoleScroll = consolePanel.gameObject.AddComponent<ScrollRect>();
            consoleScroll.horizontal = false;
            consoleScroll.vertical = true;

            var viewport = new GameObject("Viewport", typeof(RectMask2D), typeof(Image)).GetComponent<RectTransform>();
            viewport.SetParent(consolePanel, false);
            viewport.anchorMin = Vector2.zero;
            viewport.anchorMax = Vector2.one;
            viewport.pivot = new Vector2(0, 1);
            viewport.offsetMin = Vector2.zero;
            viewport.offsetMax = Vector2.zero;
            var vpImg = viewport.GetComponent<Image>();
            vpImg.color = new Color(0, 0, 0, 0); // panel already has background

            _consoleText = MakeLabel(viewport, "", 18, new Vector2(8, -8), new Vector2(0, 1), new Vector2(0, 1), color: Color.white);
            _consoleText.textWrappingMode = TextWrappingModes.Normal;
            _consoleText.alignment = TextAlignmentOptions.TopLeft;
            var fitter = _consoleText.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;
            var crt = _consoleText.rectTransform;
            crt.anchorMin = new Vector2(0, 1);
            crt.anchorMax = new Vector2(1, 1);
            crt.pivot = new Vector2(0, 1);
            crt.offsetMin = new Vector2(8, 0);
            crt.offsetMax = new Vector2(-8, 0);

            consoleScroll.content = crt;
            consoleScroll.viewport = viewport;

            _console = consolePanel.gameObject.AddComponent<ConsoleLogSink>();
            _console.consoleText = _consoleText;

            // Clock top-right beneath time controls
            _clock = MakeLabel(canvasGo.transform, "Clock: Day 1 | 00:00 | T+00:00:00", 20,
                pos: new Vector2(-16, -146), anchor: new Vector2(1, 1), pivot: new Vector2(1, 1), color: Color.white, shadow: true);

            // Charts bottom-right
            _incomeChart = MakeChart(canvasGo.transform, "IncomeChart", new Vector2(320, 140), new Vector2(-340, 20));
            _trafficChart = MakeStackedChart(canvasGo.transform, "TrafficChart", new Vector2(320, 140), new Vector2(-340, 190));

            // Upgrades on left side, build queue under it
            _upgradesContent = CreateListPanel(canvasGo.transform, new Vector2(16, -100), new Vector2(360, 260), anchorMin: new Vector2(0, 1), anchorMax: new Vector2(0, 1));
            _buildContent = CreateListPanel(canvasGo.transform, new Vector2(16, -380), new Vector2(360, 160), anchorMin: new Vector2(0, 1), anchorMax: new Vector2(0, 1));
        }

        private RectTransform CreateListPanel(Transform parent, Vector2 pos, Vector2 size, Vector2? anchorMin = null, Vector2? anchorMax = null)
        {
            // Scrollable list panel to prevent text overlap.
            var amin = anchorMin ?? new Vector2(1, 1);
            var amax = anchorMax ?? new Vector2(1, 1);
            var panel = CreatePanel(parent, pos, size, amin, amax);

            var scroll = panel.gameObject.AddComponent<ScrollRect>();
            scroll.horizontal = false;
            scroll.vertical = true;

            var viewport = new GameObject("Viewport", typeof(RectMask2D), typeof(Image)).GetComponent<RectTransform>();
            viewport.SetParent(panel, false);
            viewport.anchorMin = Vector2.zero;
            viewport.anchorMax = Vector2.one;
            viewport.pivot = new Vector2(0, 1);
            viewport.offsetMin = Vector2.zero;
            viewport.offsetMax = Vector2.zero;
            var vpImg = viewport.GetComponent<Image>();
            vpImg.color = new Color(0, 0, 0, 0.25f);

            var content = new GameObject("Content", typeof(RectTransform)).GetComponent<RectTransform>();
            content.SetParent(viewport, false);
            content.anchorMin = new Vector2(0, 1);
            content.anchorMax = new Vector2(1, 1);
            content.pivot = new Vector2(0, 1);
            content.anchoredPosition = Vector2.zero;
            content.sizeDelta = new Vector2(0, 0);

            var vlg = content.gameObject.AddComponent<VerticalLayoutGroup>();
            vlg.padding = new RectOffset(6, 6, 6, 6);
            vlg.spacing = 6f;
            vlg.childForceExpandHeight = false;
            vlg.childForceExpandWidth = true;

            var fitter = content.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;
            fitter.horizontalFit = ContentSizeFitter.FitMode.Unconstrained;

            scroll.content = content;
            scroll.viewport = viewport;

            return content;
        }

        private void Update()
        {
            _chartTimer += Time.deltaTime;
            _statusTimer += Time.deltaTime;
            if (_chartTimer >= 1f)
            {
                _chartTimer = 0f;
                if (simState != null)
                {
                    _incomeChart?.SetData(simState.dailyIncome, simState.bank);
                    _trafficChart?.SetData(simState.dailyReceived, simState.dailyMissed);
                }
            }

            if (_clock != null && simState != null)
                _clock.text = $"Clock: Day {simState.dayIndex} | {simState.GetClockHHMM()} | T+{FormatTotalTime(simState.timeSeconds)}";

            if (_status != null && _statusTimer >= 0.3f)
            {
                _statusTimer = 0f;
                _status.text = BuildStatus();
            }
        }

        private string FormatTotalTime(float seconds)
        {
            int total = Mathf.FloorToInt(seconds);
            int h = total / 3600;
            int m = (total / 60) % 60;
            int s = total % 60;
            return $"{h:00}:{m:00}:{s:00}";
        }

        private string BuildStatus()
        {
            int length = runway != null ? Mathf.RoundToInt(runway.LengthMeters) : 0;
            int smallFree = 0, smallTotal = 0;
            int medFree = 0, medTotal = 0;
            int largeFree = 0, largeTotal = 0;
            if (standManager != null)
            {
                var s = standManager.StatsForClass("ga_small");
                smallTotal = s.total; smallFree = s.free;
                var m = standManager.StatsForClass("ga_medium");
                medTotal = m.total; medFree = m.free;
                var r = standManager.StatsForClass("regional");
                var n = standManager.StatsForClass("narrowbody");
                var w = standManager.StatsForClass("widebody");
                largeTotal = r.total + n.total + w.total;
                largeFree = r.free + n.free + w.free;
            }
            return $"Rwy: {length}m | Stands S:{smallFree}/{smallTotal} M:{medFree}/{medTotal} L:{largeFree}/{largeTotal}";
        }

        private void SetTimeScale(float val)
        {
            if (simController != null) simController.SetTimeScale(val);
            UpdateBankLabel();
        }

        private void OnBank(float value)
        {
            // Keep local SimState copy in sync for charts/fallback.
            if (simState != null)
                simState.bank = value;
            UpdateBankLabel();
            RefreshUpgrades();
        }
        private void OnTimeScale(float value) => UpdateBankLabel();
        private void OnConstructionUpdated() => RefreshBuildQueue();

        private void UpdateBankLabel()
        {
            if (_bank == null) return;
            float ts = simController != null ? simController.GetTimeScale() : 1f;
            float bankVal = simState != null ? simState.bank : 0f;
            _bank.text = $"Time x{ts:0.0} | Bank: ${bankVal:0}";
        }

        private void RefreshUpgrades()
        {
            if (_upgradesContent == null || catalog == null || upgradeManager == null) return;
            foreach (Transform child in _upgradesContent) Destroy(child.gameObject);
            var upgrades = catalog.Upgrades;
            if (upgrades == null) return;
            foreach (var u in upgrades)
            {
                var label = $"{u.displayName} (${u.cost})";
                var btn = CreateButton(_upgradesContent, label, new Vector2(0, 36));
                string id = u.id;
                int purchased = upgradeManager.GetPurchaseCount(id);
                bool underConstruction = upgradeManager.IsUnderConstruction(id);
                bool soldOut = u.maxPurchases > 0 && purchased >= u.maxPurchases;
                bool affordable = simState != null && simState.bank >= u.cost;
                btn.interactable = !soldOut && !underConstruction && affordable;
                btn.onClick.AddListener(() =>
                {
                    if (upgradeManager.Purchase(id))
                    {
                        RefreshBuildQueue();
                        RefreshUpgrades();
                    }
                });
            }
        }

        private void RefreshBuildQueue()
        {
            if (_buildContent == null || upgradeManager == null) return;
            foreach (Transform child in _buildContent) Destroy(child.gameObject);
            var entries = upgradeManager.GetConstructionEntries();
            foreach (var e in entries)
            {
                var lbl = MakeLabel(_buildContent, $"{e.displayName} - {Mathf.CeilToInt(e.remainingSeconds)}s", 16, Vector2.zero, new Vector2(0, 1), new Vector2(0, 1));
                lbl.alignment = TextAlignmentOptions.Left;
            }
        }

        private RectTransform CreatePanel(Transform parent, Vector2 anchoredPos, Vector2 size, Vector2 anchorMin, Vector2 anchorMax, Vector2? pivotOverride = null)
        {
            var go = new GameObject("Panel");
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = anchorMin;
            rt.anchorMax = anchorMax;
            rt.pivot = pivotOverride ?? new Vector2(0, 1);
            rt.anchoredPosition = anchoredPos;
            rt.sizeDelta = size;
            var img = go.AddComponent<Image>();
            img.color = new Color(0, 0, 0, 0.35f);
            return rt;
        }

        private TMP_Text MakeLabel(Transform parent, string text, int size, Vector2 pos, Vector2? anchor = null, Vector2? pivot = null, Color? color = null, bool shadow = false)
        {
            var go = new GameObject("Text");
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.anchorMin = anchor ?? new Vector2(0, 1);
            rt.anchorMax = anchor ?? new Vector2(0, 1);
            rt.pivot = pivot ?? new Vector2(0, 1);
            rt.anchoredPosition = pos;
            rt.sizeDelta = new Vector2(300, 30);
            var txt = go.AddComponent<TextMeshProUGUI>();
            txt.text = text;
            txt.fontSize = size;
            txt.color = color ?? Color.white;
            txt.alignment = TextAlignmentOptions.Left;
            if (shadow)
            {
                var sh = go.AddComponent<UnityEngine.UI.Shadow>();
                sh.effectColor = new Color(0, 0, 0, 0.7f);
                sh.effectDistance = new Vector2(1.5f, -1.5f);
            }
            return txt;
        }

        private IncomeBarChart MakeChart(Transform parent, string name, Vector2 size, Vector2 pos)
        {
            // Root container with background image.
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            var rt = root.AddComponent<RectTransform>();
            rt.anchorMin = new Vector2(1, 0);
            rt.anchorMax = new Vector2(1, 0);
            rt.pivot = new Vector2(1, 0);
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            var bg = root.AddComponent<Image>();
            bg.color = new Color(0, 0, 0, 0.35f);

            // Child graphic for the actual chart (only one Graphic per GO).
            var chartGo = new GameObject(name + "_Graphic");
            chartGo.transform.SetParent(root.transform, false);
            var crt = chartGo.AddComponent<RectTransform>();
            crt.anchorMin = Vector2.zero;
            crt.anchorMax = Vector2.one;
            crt.pivot = new Vector2(0.5f, 0.5f);
            crt.offsetMin = Vector2.zero;
            crt.offsetMax = Vector2.zero;

            var chart = chartGo.AddComponent<IncomeBarChart>();
            chart.raycastTarget = false;
            return chart;
        }

        private StackedBarChart MakeStackedChart(Transform parent, string name, Vector2 size, Vector2 pos)
        {
            var root = new GameObject(name);
            root.transform.SetParent(parent, false);
            var rt = root.AddComponent<RectTransform>();
            rt.anchorMin = new Vector2(1, 0);
            rt.anchorMax = new Vector2(1, 0);
            rt.pivot = new Vector2(1, 0);
            rt.anchoredPosition = pos;
            rt.sizeDelta = size;
            var bg = root.AddComponent<Image>();
            bg.color = new Color(0, 0, 0, 0.35f);

            var chartGo = new GameObject(name + "_Graphic");
            chartGo.transform.SetParent(root.transform, false);
            var crt = chartGo.AddComponent<RectTransform>();
            crt.anchorMin = Vector2.zero;
            crt.anchorMax = Vector2.one;
            crt.pivot = new Vector2(0.5f, 0.5f);
            crt.offsetMin = Vector2.zero;
            crt.offsetMax = Vector2.zero;

            var chart = chartGo.AddComponent<StackedBarChart>();
            chart.raycastTarget = false;
            return chart;
        }

        private Button CreateButton(Transform parent, string label, Vector2 size)
        {
            var go = new GameObject(label);
            go.transform.SetParent(parent, false);
            var rt = go.AddComponent<RectTransform>();
            rt.sizeDelta = size;
            var img = go.AddComponent<Image>();
            img.color = new Color(0.2f, 0.6f, 1f, 0.8f);
            var btn = go.AddComponent<Button>();
            var le = go.AddComponent<LayoutElement>();
            le.minHeight = size.y;
            le.preferredHeight = size.y;
            le.flexibleWidth = 1f; // stretch to parent width
            var txtGo = new GameObject("Label");
            txtGo.transform.SetParent(go.transform, false);
            var txt = txtGo.AddComponent<TextMeshProUGUI>();
            txt.text = label;
            txt.textWrappingMode = TextWrappingModes.Normal;
            txt.fontSize = 16;
            txt.color = Color.white;
            txt.alignment = TextAlignmentOptions.Left;
            var txtRt = txtGo.GetComponent<RectTransform>();
            txtRt.anchorMin = Vector2.zero;
            txtRt.anchorMax = Vector2.one;
            txtRt.offsetMin = txtRt.offsetMax = Vector2.zero;
            return btn;
        }

        private void EnsureEventSystem()
        {
            if (EventSystem.current == null)
            {
                var es = new GameObject("EventSystem");
                es.AddComponent<EventSystem>();
#if ENABLE_INPUT_SYSTEM
                es.AddComponent<InputSystemUIInputModule>();
#else
                es.AddComponent<StandaloneInputModule>();
#endif
            }
        }
    }
}
