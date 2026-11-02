using UnityEngine;

public class SceneBootstrap : MonoBehaviour
{
    [Header("Prefab References (optional)")]
    [SerializeField] private GameObject playerPrefab;

    [Header("Test Floor")]
    [SerializeField] private float floorSize = 50f;
    [SerializeField] private Material floorMaterial;

    private void Awake()
    {
        if (Camera.main == null)
            SetupCamera();

        if (GameObject.FindGameObjectWithTag("Player") == null)
            SetupPlayer();

        SetupFloor();
        SetupLighting();
    }

    private void SetupPlayer()
    {
        if (playerPrefab != null)
        {
            Instantiate(playerPrefab, Vector3.up * 1f, Quaternion.identity);
            return;
        }

        // Placeholder capsule player
        GameObject player = GameObject.CreatePrimitive(PrimitiveType.Capsule);
        player.name = "Player";
        player.tag = "Player";
        player.transform.position = new Vector3(0f, 1.5f, 0f);
        player.layer = LayerMask.NameToLayer("Default");

        Rigidbody rb = player.AddComponent<Rigidbody>();
        rb.mass = 1f;
        rb.freezeRotation = true;
        rb.interpolation = RigidbodyInterpolation.Interpolate;
        rb.collisionDetectionMode = CollisionDetectionMode.Continuous;

        player.AddComponent<PlayerMovement>();

        // Color the player
        var renderer = player.GetComponent<Renderer>();
        if (renderer != null)
        {
            var mat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mat.color = new Color(0.9f, 0.85f, 0.75f); // paper-ish color
            renderer.material = mat;
        }
    }

    private void SetupCamera()
    {
        GameObject camObj = new GameObject("Main Camera");
        camObj.tag = "MainCamera";
        Camera cam = camObj.AddComponent<Camera>();
        cam.fieldOfView = 60f;
        cam.nearClipPlane = 0.1f;
        cam.farClipPlane = 500f;
        camObj.AddComponent<AudioListener>();
        camObj.AddComponent<ThirdPersonCamera>();
    }

    private void SetupFloor()
    {
        if (GameObject.Find("Floor") != null) return;

        GameObject floor = GameObject.CreatePrimitive(PrimitiveType.Cube);
        floor.name = "Floor";
        floor.transform.position = Vector3.zero;
        floor.transform.localScale = new Vector3(floorSize, 0.2f, floorSize);
        floor.isStatic = true;
        floor.layer = LayerMask.NameToLayer("Default");

        var renderer = floor.GetComponent<Renderer>();
        if (renderer != null && floorMaterial == null)
        {
            var mat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mat.color = new Color(0.75f, 0.82f, 0.7f);
            renderer.material = mat;
        }

        // Add some obstacles for camera collision testing
        CreateObstacle(new Vector3(5f, 1.5f, 5f), new Vector3(2f, 3f, 2f));
        CreateObstacle(new Vector3(-4f, 1f, 8f), new Vector3(3f, 2f, 1f));
        CreateObstacle(new Vector3(8f, 2f, -3f), new Vector3(1.5f, 4f, 1.5f));
        CreateObstacle(new Vector3(-7f, 0.75f, -6f), new Vector3(4f, 1.5f, 2f));
    }

    private void CreateObstacle(Vector3 position, Vector3 scale)
    {
        GameObject obs = GameObject.CreatePrimitive(PrimitiveType.Cube);
        obs.name = "Obstacle";
        obs.transform.position = position;
        obs.transform.localScale = scale;
        obs.isStatic = true;

        var renderer = obs.GetComponent<Renderer>();
        if (renderer != null)
        {
            var mat = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            mat.color = new Color(
                Random.Range(0.7f, 0.95f),
                Random.Range(0.7f, 0.9f),
                Random.Range(0.65f, 0.85f)
            );
            renderer.material = mat;
        }
    }

    private void SetupLighting()
    {
        if (FindFirstObjectByType<Light>() != null) return;

        GameObject lightObj = new GameObject("Directional Light");
        Light light = lightObj.AddComponent<Light>();
        light.type = LightType.Directional;
        light.intensity = 1.2f;
        light.color = new Color(1f, 0.96f, 0.9f);
        light.shadows = LightShadows.Soft;
        lightObj.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
    }
}
