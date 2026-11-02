using UnityEngine;

public class ThirdPersonCamera : MonoBehaviour
{
    [Header("Target")]
    [SerializeField] private Transform target;
    [SerializeField] private Vector3 shoulderOffset = new Vector3(0.5f, 1.6f, 0f);

    [Header("Distance")]
    [SerializeField] private float defaultDistance = 3.5f;
    [SerializeField] private float minDistance = 1f;
    [SerializeField] private float maxDistance = 6f;
    [SerializeField] private float scrollSpeed = 2f;

    [Header("Sensitivity")]
    [SerializeField] private float mouseSensitivity = 3f;
    [SerializeField] private float minSensitivity = 0.5f;
    [SerializeField] private float maxSensitivity = 10f;

    [Header("Rotation Limits")]
    [SerializeField] private float minPitch = -35f;
    [SerializeField] private float maxPitch = 60f;

    [Header("Collision")]
    [SerializeField] private float collisionRadius = 0.2f;
    [SerializeField] private LayerMask collisionLayers;
    [SerializeField] private float collisionRecoverSpeed = 10f;

    [Header("Smoothing")]
    [SerializeField] private float positionSmoothTime = 0.08f;
    [SerializeField] private float rotationSmoothSpeed = 15f;

    private float yaw;
    private float pitch;
    private float currentDistance;
    private float targetDistance;
    private Vector3 currentVelocity;

    private void Awake()
    {
        targetDistance = defaultDistance;
        currentDistance = defaultDistance;
        Cursor.lockState = CursorLockMode.Locked;
        Cursor.visible = false;
    }

    private void Start()
    {
        if (target == null)
        {
            var player = GameObject.FindGameObjectWithTag("Player");
            if (player != null) target = player.transform;
        }

        Vector3 angles = transform.eulerAngles;
        yaw = angles.y;
        pitch = angles.x;
    }

    private void LateUpdate()
    {
        if (target == null) return;

        HandleInput();
        UpdatePosition();
    }

    private void HandleInput()
    {
        if (Cursor.lockState != CursorLockMode.Locked) return;

        float mouseX = Input.GetAxis("Mouse X") * mouseSensitivity;
        float mouseY = Input.GetAxis("Mouse Y") * mouseSensitivity;

        yaw += mouseX;
        pitch -= mouseY;
        pitch = Mathf.Clamp(pitch, minPitch, maxPitch);

        float scroll = Input.GetAxis("Mouse ScrollWheel");
        if (Mathf.Abs(scroll) > 0.01f)
        {
            targetDistance -= scroll * scrollSpeed;
            targetDistance = Mathf.Clamp(targetDistance, minDistance, maxDistance);
        }
    }

    private void UpdatePosition()
    {
        Quaternion rotation = Quaternion.Euler(pitch, yaw, 0f);

        Vector3 pivotPoint = target.position + rotation * shoulderOffset;

        float desiredDistance = targetDistance;
        float adjustedDistance = CheckCollision(pivotPoint, rotation, desiredDistance);

        currentDistance = Mathf.Lerp(currentDistance, adjustedDistance, collisionRecoverSpeed * Time.deltaTime);

        Vector3 desiredPosition = pivotPoint - rotation * Vector3.forward * currentDistance;
        transform.position = Vector3.SmoothDamp(transform.position, desiredPosition, ref currentVelocity, positionSmoothTime);

        Quaternion targetRotation = Quaternion.LookRotation(pivotPoint - transform.position);
        transform.rotation = Quaternion.Slerp(transform.rotation, targetRotation, rotationSmoothSpeed * Time.deltaTime);
    }

    private float CheckCollision(Vector3 pivot, Quaternion rotation, float desiredDist)
    {
        Vector3 direction = -(rotation * Vector3.forward);

        if (Physics.SphereCast(pivot, collisionRadius, direction, out RaycastHit hit, desiredDist, collisionLayers))
            return hit.distance - collisionRadius * 0.5f;

        return desiredDist;
    }

    public void SetSensitivity(float value)
    {
        mouseSensitivity = Mathf.Clamp(value, minSensitivity, maxSensitivity);
    }

    public float GetSensitivity() => mouseSensitivity;
    public float MinSensitivity => minSensitivity;
    public float MaxSensitivity => maxSensitivity;

    public void ToggleCursor()
    {
        if (Cursor.lockState == CursorLockMode.Locked)
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
        }
        else
        {
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }
    }
}
