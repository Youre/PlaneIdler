using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace PlaneIdler.Systems
{
    public class OllamaClient : MonoBehaviour
    {
        [Header("Ollama")]
        public string endpoint = "http://localhost:11434/api/generate";
        public string model = "llama3";
        public float temperature = 0.7f;

        public void Query(string prompt, System.Action<string> onDone)
        {
            StartCoroutine(Send(prompt, onDone));
        }

        private IEnumerator Send(string prompt, System.Action<string> onDone)
        {
            var payload = JsonUtility.ToJson(new Request { model = model, prompt = prompt, temperature = temperature, stream = false });
            var req = new UnityWebRequest(endpoint, "POST");
            byte[] bodyRaw = System.Text.Encoding.UTF8.GetBytes(payload);
            req.uploadHandler = new UploadHandlerRaw(bodyRaw);
            req.downloadHandler = new DownloadHandlerBuffer();
            req.SetRequestHeader("Content-Type", "application/json");
            yield return req.SendWebRequest();

            if (req.result != UnityWebRequest.Result.Success)
            {
                Debug.LogError($"OllamaClient error: {req.error}");
                onDone?.Invoke($"[error] {req.error}");
            }
            else
            {
                onDone?.Invoke(req.downloadHandler.text);
            }
        }

        [System.Serializable]
        private class Request
        {
            public string model;
            public string prompt;
            public float temperature;
            public bool stream;
        }
    }
}
