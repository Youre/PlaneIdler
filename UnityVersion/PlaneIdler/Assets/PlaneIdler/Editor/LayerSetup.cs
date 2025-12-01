using UnityEditor;

/// <summary>
/// Ensures common physics layers exist (Aircraft, Runway, Ground, UI).
/// Run via Tools/PlaneIdler/Setup Layers.
/// </summary>
public static class LayerSetup
{
    private static readonly string[] Needed = { "Aircraft", "Runway", "Ground", "UI" };

    [MenuItem("Tools/PlaneIdler/Setup Layers")]
    public static void EnsureLayers()
    {
        var tagManager = new SerializedObject(AssetDatabase.LoadAllAssetsAtPath("ProjectSettings/TagManager.asset")[0]);
        var layersProp = tagManager.FindProperty("layers");
        foreach (var name in Needed)
        {
            bool exists = false;
            for (int i = 8; i < layersProp.arraySize; i++) // user layers start at 8
            {
                var sp = layersProp.GetArrayElementAtIndex(i);
                if (sp.stringValue == name)
                {
                    exists = true;
                    break;
                }
            }
            if (!exists)
            {
                for (int i = 8; i < layersProp.arraySize; i++)
                {
                    var sp = layersProp.GetArrayElementAtIndex(i);
                    if (string.IsNullOrEmpty(sp.stringValue))
                    {
                        sp.stringValue = name;
                        break;
                    }
                }
            }
        }
        tagManager.ApplyModifiedProperties();
        AssetDatabase.SaveAssets();
    }
}
