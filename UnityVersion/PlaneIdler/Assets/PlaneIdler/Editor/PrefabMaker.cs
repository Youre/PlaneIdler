using UnityEditor;
using UnityEngine;

// Creates simple placeholder prefabs for core game objects.
// Run via menu: Tools/PlaneIdler/Create Prefabs
public static class PrefabMaker
{
    private const string PrefabRoot = "Assets/PlaneIdler/Prefabs";

    [MenuItem("Tools/PlaneIdler/Create Prefabs")]
    public static void CreatePrefabs()
    {
        CreateAirportRoot();
        CreateRunway();
        CreateStand();
        CreateFuelStation();
        CreateAircraftActor();
        CreateSystemsRoot();
        AssetDatabase.SaveAssets();
        AssetDatabase.Refresh();
        Debug.Log("PlaneIdler placeholder prefabs created.");
    }

    private static void CreateAirportRoot()
    {
        var go = new GameObject("Airport");
        go.AddComponent<PlaneIdler.Airport.AirportManager>();
        go.AddComponent<PlaneIdler.Airport.StandManager>();
        go.AddComponent<PlaneIdler.Airport.Tower>();
        Save(go, $"{PrefabRoot}/Airport/Airport.prefab");
    }

    private static void CreateRunway()
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cube);
        go.name = "Runway";
        // Godot runway mesh size: length 600m, width 30m, height 0.5m.
        go.transform.localScale = new Vector3(600f, 0.5f, 30f);
        go.GetComponent<Renderer>().sharedMaterial = MakeMat(new Color(0.2f, 0.5f, 0.25f)); // grass default
        go.AddComponent<PlaneIdler.Airport.Runway>();
        var layer = LayerMask.NameToLayer("Runway");
        go.layer = layer >= 0 ? layer : 0;
        Save(go, $"{PrefabRoot}/Runway/Runway.prefab");
    }

    private static void CreateStand()
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        go.name = "Stand";
        // Godot stand: radius 8m, height 0.25m -> cylinder diameter 16m, height 0.25.
        go.transform.localScale = new Vector3(16f, 0.125f, 16f);
        go.GetComponent<Renderer>().sharedMaterial = MakeMat(new Color(0.1f, 0.6f, 1.0f)); // ga_small default tint
        go.AddComponent<PlaneIdler.Airport.Stand>();
        var layer = LayerMask.NameToLayer("Ground");
        go.layer = layer >= 0 ? layer : 0;
        Save(go, $"{PrefabRoot}/Stand/Stand.prefab");
    }

    private static void CreateFuelStation()
    {
        var go = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        go.name = "FuelStation";
        go.transform.localScale = new Vector3(2f, 1f, 2f);
        go.AddComponent<PlaneIdler.Airport.FuelStation>();
        var layer = LayerMask.NameToLayer("Ground");
        go.layer = layer >= 0 ? layer : 0;
        Save(go, $"{PrefabRoot}/FuelStation/FuelStation.prefab");
    }

    private static void CreateAircraftActor()
    {
        var go = new GameObject("AircraftActor");
        var controller = go.AddComponent<CharacterController>();
        controller.height = 2f;
        controller.radius = 0.5f;
        go.AddComponent<PlaneIdler.Actors.AircraftActor>();
        var path = $"{PrefabRoot}/AircraftActor/AircraftActor.prefab";
        Save(go, path);
        EnsureResourcesCopy(path, "Assets/PlaneIdler/Resources/Prefabs/AircraftActor.prefab");
    }

    private static void CreateSystemsRoot()
    {
        var go = new GameObject("Systems");
        go.AddComponent<PlaneIdler.Systems.CatalogLoader>();
        go.AddComponent<PlaneIdler.Systems.UpgradeManager>();
        go.AddComponent<PlaneIdler.Sim.SimController>();
        go.AddComponent<PlaneIdler.Sim.ArrivalGenerator>();
        go.AddComponent<PlaneIdler.Systems.OllamaClient>();
        go.AddComponent<PlaneIdler.Systems.LlmAgent>();
        Save(go, $"{PrefabRoot}/SystemsRoot/Systems.prefab");
    }

    private static Material MakeMat(Color c)
    {
        var shader = Shader.Find("Universal Render Pipeline/Lit");
        if (shader == null)
        {
            shader = Shader.Find("Standard");
        }
        if (shader == null)
        {
            Debug.LogWarning("PrefabMaker: no suitable shader found, using built-in default.");
            return null;
        }
        var mat = new Material(shader);
        mat.color = c;
        return mat;
    }

    private static void EnsureResourcesCopy(string sourcePath, string destPath)
    {
        var dir = System.IO.Path.GetDirectoryName(destPath).Replace("\\", "/");
        if (!AssetDatabase.IsValidFolder("Assets/PlaneIdler/Resources"))
        {
            AssetDatabase.CreateFolder("Assets/PlaneIdler", "Resources");
        }
        if (!AssetDatabase.IsValidFolder(dir))
        {
            var parent = "Assets";
            foreach (var part in destPath.Split('/')[1..^1])
            {
                var candidate = $"{parent}/{part}";
                if (!AssetDatabase.IsValidFolder(candidate))
                {
                    AssetDatabase.CreateFolder(parent, part);
                }
                parent = candidate;
            }
        }
        AssetDatabase.CopyAsset(sourcePath, destPath);
    }

    private static void Save(GameObject go, string path)
    {
        var prefab = PrefabUtility.SaveAsPrefabAsset(go, path);
        Object.DestroyImmediate(go);
    }
}
