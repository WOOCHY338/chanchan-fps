using UnityEngine;

public class PlayerMovement : MonoBehaviour
{
    [Header("Movement")]
    [SerializeField] private float walkSpeed = 5f;
    [SerializeField] private float sprintSpeed = 8.5f;
    [SerializeField] private float acceleration = 10f;
    [SerializeField] private float deceleration = 12f;

    [Header("Jump")]
    [SerializeField] private float jumpForce = 7f;
    [SerializeField] private float groundCheckRadius = 0.3f;
    [SerializeField] private LayerMask groundLayer;

    [Header("Physics")]
    [SerializeField] private float gravityMultiplier = 2.5f;
    [SerializeField] private float maxFallSpeed = 20f;

    private Rigidbody rb;
    private Transform cameraTransform;
    private Vector3 moveDirection;
    private float currentSpeed;
    private bool isGrounded;
    private bool jumpRequested;

    private void Awake()
    {
        rb = GetComponent<Rigidbody>();
        rb.freezeRotation = true;
        rb.interpolation = RigidbodyInterpolation.Interpolate;
        rb.collisionDetectionMode = CollisionDetectionMode.Continuous;
    }

    private void Start()
    {
        cameraTransform = Camera.main.transform;
    }

    private void Update()
    {
        ReadInput();
        CheckGround();
    }

    private void FixedUpdate()
    {
        ApplyMovement();
        ApplyGravity();
    }

    private void ReadInput()
    {
        float h = Input.GetAxisRaw("Horizontal");
        float v = Input.GetAxisRaw("Vertical");

        Vector3 camForward = cameraTransform.forward;
        Vector3 camRight = cameraTransform.right;
        camForward.y = 0f;
        camRight.y = 0f;
        camForward.Normalize();
        camRight.Normalize();

        moveDirection = (camForward * v + camRight * h).normalized;

        bool isSprinting = Input.GetKey(KeyCode.LeftShift);
        float targetSpeed = moveDirection.magnitude > 0.1f
            ? (isSprinting ? sprintSpeed : walkSpeed)
            : 0f;

        float smoothRate = targetSpeed > currentSpeed ? acceleration : deceleration;
        currentSpeed = Mathf.MoveTowards(currentSpeed, targetSpeed, smoothRate * Time.deltaTime);

        if (Input.GetKeyDown(KeyCode.Space) && isGrounded)
            jumpRequested = true;

        if (moveDirection.magnitude > 0.1f)
        {
            Quaternion targetRotation = Quaternion.LookRotation(moveDirection);
            transform.rotation = Quaternion.Slerp(transform.rotation, targetRotation, 10f * Time.deltaTime);
        }
    }

    private void CheckGround()
    {
        Vector3 origin = transform.position + Vector3.up * 0.1f;
        isGrounded = Physics.SphereCast(origin, groundCheckRadius, Vector3.down, out _, 0.3f, groundLayer);
    }

    private void ApplyMovement()
    {
        Vector3 velocity = moveDirection * currentSpeed;
        velocity.y = rb.linearVelocity.y;
        rb.linearVelocity = velocity;

        if (jumpRequested)
        {
            rb.linearVelocity = new Vector3(rb.linearVelocity.x, 0f, rb.linearVelocity.z);
            rb.AddForce(Vector3.up * jumpForce, ForceMode.Impulse);
            jumpRequested = false;
        }
    }

    private void ApplyGravity()
    {
        if (!isGrounded && rb.linearVelocity.y < 0f)
        {
            Vector3 extraGravity = Vector3.down * (gravityMultiplier - 1f) * Physics.gravity.magnitude;
            rb.AddForce(extraGravity, ForceMode.Acceleration);
        }

        if (rb.linearVelocity.y < -maxFallSpeed)
            rb.linearVelocity = new Vector3(rb.linearVelocity.x, -maxFallSpeed, rb.linearVelocity.z);
    }

    public float CurrentSpeed => currentSpeed;
    public bool IsGrounded => isGrounded;
    public bool IsSprinting => Input.GetKey(KeyCode.LeftShift) && currentSpeed > walkSpeed * 0.9f;
}
