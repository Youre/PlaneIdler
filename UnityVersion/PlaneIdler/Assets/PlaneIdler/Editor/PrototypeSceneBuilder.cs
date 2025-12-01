using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

// Generates a simple playable Unity scene from scratch so the team can iterate
// without hand-placing boilerplate objects. Safe to rerun; it overwrites the
// prototype scene only.
public static class PrototypeSceneBuilder
{
    private const string ScenePath = "Assets/PlaneIdler/Scenes/Prototype_Main.unity";
    private const string GrassPath = "Assets/PlaneIdler/Art/grass.jpg";

    [MenuItem("Tools/PlaneIdler/Build Prototype Scene")]
    public static void BuildScene()
    {
        // Start with an empty scene.
        var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

        CreateCinematicCamera();
        CreateLight();
        CreateGround();
        CreateGameSystems();
        CreateAirportLayout();
        CreateHud();

        // Save the scene (overwrites only the prototype scene path).
        EditorSceneManager.SaveScene(scene, ScenePath, true);
        AssetDatabase.Refresh();
        Debug.Log($"Prototype scene generated at {ScenePath}");
    }

    private static void CreateCinematicCamera()
    {
        var camGo = new GameObject("Main Camera");
        var cam = camGo.AddComponent<Camera>();
        cam.tag = "MainCamera";
        cam.transform.position = new Vector3(0f, 70f, -120f);
        cam.transform.rotation = Quaternion.Euler(55f, 20f, 0f);
        var auto = camGo.AddComponent<PlaneIdler.Systems.CameraAutoOrbit>();
        auto.center = Vector3.zero;
        auto.radius = 120f;
        auto.height = 70f;
        auto.angularSpeed = 8f;
        auto.pitchDegrees = 55f;
    }

    private static void CreateLight()
    {
        var lightGo = new GameObject("Sun");
        var light = lightGo.AddComponent<Light>();
        light.type = LightType.Directional;
        light.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
        light.intensity = 1.2f;

        var moonGo = new GameObject("Moon");
        var moon = moonGo.AddComponent<Light>();
        moon.type = LightType.Directional;
        moon.color = new Color(0.6f, 0.7f, 1f);
        moon.intensity = 0.2f;
        moon.transform.rotation = Quaternion.Euler(-130f, 30f, 0f);

        var tod = lightGo.AddComponent<PlaneIdler.Systems.DayNightController>();
        tod.sun = light;
        tod.moon = moon;
    }

    private static void CreateGround()
    {
        var ground = GameObject.CreatePrimitive(PrimitiveType.Plane);
        ground.name = "Ground";
        // Godot ground mesh size 4800x4800; Unity plane default is 10x10, so scale to 480x480.
        ground.transform.localScale = new Vector3(480f, 1f, 480f);

        var grassTex = AssetDatabase.LoadAssetAtPath<Texture2D>(GrassPath);
        var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");

        if (shader != null)
        {
            var mat = new Material(shader);
            if (grassTex != null)
            {
                // Ensure the grass tiles instead of stretching from the edge.
                grassTex.wrapMode = TextureWrapMode.Repeat;
                mat.mainTexture = grassTex;
                mat.mainTextureScale = new Vector2(16f, 16f); // matches Godot UV scale
            }
            var renderer = ground.GetComponent<MeshRenderer>();
            renderer.sharedMaterial = mat;
        }
    }

    private static void CreateGameSystems()
    {
        var systemsPrefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/PlaneIdler/Prefabs/SystemsRoot/Systems.prefab");
        if (systemsPrefab != null)
        {
            var instance = (GameObject)PrefabUtility.InstantiatePrefab(systemsPrefab);
            WireSystems(instance);
        }
        else
        {
            var systems = new GameObject("Systems");
            systems.AddComponent<PlaneIdler.Systems.CatalogLoader>();
            systems.AddComponent<PlaneIdler.Systems.UpgradeManager>();

            var simGo = new GameObject("Sim");
            simGo.transform.SetParent(systems.transform);
            simGo.AddComponent<PlaneIdler.Sim.SimController>();
            var state = GetOrCreateSimStateAsset();
        }
    }

    private static void CreateAirportLayout()
    {
        var airportPrefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/PlaneIdler/Prefabs/Airport/Airport.prefab");
        var runwayPrefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/PlaneIdler/Prefabs/Runway/Runway.prefab");
        var standPrefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/PlaneIdler/Prefabs/Stand/Stand.prefab");
        var fuelPrefab = AssetDatabase.LoadAssetAtPath<GameObject>("Assets/PlaneIdler/Prefabs/FuelStation/FuelStation.prefab");

        GameObject airportRoot = null;
        if (airportPrefab != null)
        {
            airportRoot = (GameObject)PrefabUtility.InstantiatePrefab(airportPrefab);
        }
        else
        {
            airportRoot = new GameObject("Airport");
            airportRoot.AddComponent<PlaneIdler.Airport.AirportManager>();
            airportRoot.AddComponent<PlaneIdler.Airport.StandManager>();
            airportRoot.AddComponent<PlaneIdler.Airport.Tower>();
        }

        // Runway
        GameObject runwayGo = null;
        if (runwayPrefab != null)
        {
            runwayGo = (GameObject)PrefabUtility.InstantiatePrefab(runwayPrefab, airportRoot.transform);
            runwayGo.transform.position = new Vector3(0f, 0.1f, 0f);
            EnsureRunwayMaterial(runwayGo);
            AddRunwayEdgeLights(runwayGo);
        }

        // Stands
        for (int i = 0; i < 4; i++)
        {
            GameObject stand;
            if (standPrefab != null)
            {
                stand = (GameObject)PrefabUtility.InstantiatePrefab(standPrefab, airportRoot.transform);
            }
            else
            {
                stand = GameObject.CreatePrimitive(PrimitiveType.Cube);
                stand.AddComponent<PlaneIdler.Airport.Stand>();
            }
            stand.name = $"Stand_{i + 1}";
            stand.transform.localScale = new Vector3(6f, 0.2f, 6f);
            stand.transform.position = new Vector3(-12f + i * 8f, 0.1f, -15f);
        }

        // Fuel station
        if (fuelPrefab != null)
        {
            var fuel = (GameObject)PrefabUtility.InstantiatePrefab(fuelPrefab, airportRoot.transform);
            fuel.transform.position = new Vector3(0f, 1f, -22f);
        }
        else
        {
            var fuel = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
            fuel.name = "FuelStation";
            fuel.transform.SetParent(airportRoot.transform);
            fuel.transform.localScale = new Vector3(2f, 1f, 2f);
            fuel.transform.position = new Vector3(0f, 1f, -22f);
            fuel.AddComponent<PlaneIdler.Airport.FuelStation>();
        }
        // Wire references if possible
        WireAirport(airportRoot, runwayGo);
        WireCamera(runwayGo);
    }

    private static void CreateHud()
    {
        var hud = new GameObject("HUD");
        hud.AddComponent<PlaneIdler.UI.HudRuntimeBuilder>();
    }

    private static PlaneIdler.Sim.SimState GetOrCreateSimStateAsset()
    {
        var path = "Assets/PlaneIdler/Settings/SimState.asset";
        var state = AssetDatabase.LoadAssetAtPath<PlaneIdler.Sim.SimState>(path);
        if (state == null)
        {
            state = ScriptableObject.CreateInstance<PlaneIdler.Sim.SimState>();
            EnsureFolder("Assets/PlaneIdler/Settings");
            AssetDatabase.CreateAsset(state, path);
        }
        return state;
    }

    private static void WireSystems(GameObject systems)
    {
        var catalog = systems.GetComponent<PlaneIdler.Systems.CatalogLoader>();
        var sim = systems.GetComponentInChildren<PlaneIdler.Sim.SimController>();
        var arrival = systems.GetComponent<PlaneIdler.Sim.ArrivalGenerator>();
        var state = GetOrCreateSimStateAsset();
        if (sim != null)
        {
            var flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance;
            sim.GetType().GetField("catalog", flags)?.SetValue(sim, catalog);
            sim.GetType().GetField("arrivalGenerator", flags)?.SetValue(sim, arrival);
            sim.GetType().GetField("simState", flags)?.SetValue(sim, state);
        }
        // Ensure catalog has JSON assigned to avoid missing Resources lookups
        if (catalog != null)
        {
            var aircraft = Resources.Load<TextAsset>("PlaneIdler/Data/aircraft") ?? Resources.Load<TextAsset>("Data/aircraft");
            var upgrades = Resources.Load<TextAsset>("PlaneIdler/Data/upgrades") ?? Resources.Load<TextAsset>("Data/upgrades");
            catalog.aircraftJson = aircraft;
            catalog.upgradesJson = upgrades;
        }
    }

    private static void WireAirport(GameObject airportRoot, GameObject runwayGo)
    {
        var airportMgr = airportRoot.GetComponent<PlaneIdler.Airport.AirportManager>();
        var standMgr = airportRoot.GetComponent<PlaneIdler.Airport.StandManager>();
        var runway = runwayGo != null ? runwayGo.GetComponent<PlaneIdler.Airport.Runway>() : null;
        var stands = airportRoot.GetComponentsInChildren<PlaneIdler.Airport.Stand>();
        if (standMgr != null)
        {
            standMgr.RegisterStands(stands);
        }
        var sim = Object.FindFirstObjectByType<PlaneIdler.Sim.SimController>();
        if (sim != null)
        {
            var flags = System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance;
            sim.GetType().GetField("standManager", flags)?.SetValue(sim, standMgr);
            sim.GetType().GetField("runway", flags)?.SetValue(sim, runway);
        }
    }

    private static void WireCamera(GameObject runwayGo)
    {
        if (runwayGo == null) return;
        var auto = Object.FindFirstObjectByType<PlaneIdler.Systems.CameraAutoOrbit>();
        if (auto != null)
        {
            auto.runwayTarget = runwayGo.transform;
        }
    }

    private static void AddRunwayEdgeLights(GameObject runwayGo)
    {
        var lightsRoot = new GameObject("RunwayLights");
        lightsRoot.transform.SetParent(runwayGo.transform);
        var length = runwayGo.transform.localScale.x;
        int count = 12;
        for (int i = 0; i < count; i++)
        {
            float t = i / (float)(count - 1);
            float x = Mathf.Lerp(-length * 0.5f + 5f, length * 0.5f - 5f, t);
            CreateEdgeLight(lightsRoot.transform, new Vector3(x, 0.6f, 15f));
            CreateEdgeLight(lightsRoot.transform, new Vector3(x, 0.6f, -15f));
        }
        lightsRoot.AddComponent<PlaneIdler.Systems.RunwayLightsController>();
    }

    private static void CreateEdgeLight(Transform parent, Vector3 localPos)
    {
        var go = new GameObject("EdgeLight");
        go.transform.SetParent(parent, false);
        go.transform.localPosition = localPos;
        var l = go.AddComponent<Light>();
        l.type = LightType.Point;
        l.range = 12f;
        l.intensity = 3f;
        l.color = new Color(0.2f, 0.6f, 1f);
    }

    private static void EnsureRunwayMaterial(GameObject runwayGo)
    {
        var renderer = runwayGo.GetComponent<Renderer>() ?? runwayGo.GetComponentInChildren<Renderer>();
        if (renderer == null) return;
        var shader = Shader.Find("Universal Render Pipeline/Lit") ?? Shader.Find("Standard");
        if (shader == null) return;

        // Always enforce a distinct dark-green runway material so it
        // stands out from the ground regardless of prefab defaults.
        var mat = renderer.sharedMaterial;
        if (mat == null || mat.shader == null || mat.shader != shader)
            mat = new Material(shader);

        mat.color = new Color(0.2f, 0.5f, 0.25f);
        renderer.sharedMaterial = mat;
    }

    private static void EnsureFolder(string folderPath)
    {
        if (!AssetDatabase.IsValidFolder(folderPath))
        {
            var segments = folderPath.Split('/');
            string current = segments[0];
            for (int i = 1; i < segments.Length; i++)
            {
                var next = current + "/" + segments[i];
                if (!AssetDatabase.IsValidFolder(next))
                    AssetDatabase.CreateFolder(current, segments[i]);
                current = next;
            }
        }
    }
}
