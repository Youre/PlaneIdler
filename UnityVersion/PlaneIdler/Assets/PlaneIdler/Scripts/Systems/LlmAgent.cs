using UnityEngine;

namespace PlaneIdler.Systems
{
    /// <summary>
    /// Minimal LLM agent wrapper; sends prompt to OllamaClient and logs response.
    /// </summary>
    public class LlmAgent : MonoBehaviour
    {
        [SerializeField] private OllamaClient client;

        private void Awake()
        {
            if (client == null) client = GetComponent<OllamaClient>();
            if (client == null) client = gameObject.AddComponent<OllamaClient>();
        }

        public void Ask(string prompt)
        {
            if (client == null)
            {
                Debug.LogWarning("LLM: client missing");
                return;
            }
            client.Query(prompt, OnResponse);
        }

        private void OnResponse(string text)
        {
            Debug.Log($"LLM response: {text}");
        }
    }
}
