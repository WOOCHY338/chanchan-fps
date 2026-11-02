using UnityEngine;

[CreateAssetMenu(fileName = "GameSettings", menuName = "ChanChan/Game Settings")]
public class GameSettings : ScriptableObject
{
    [Header("Camera")]
    public float mouseSensitivity = 3f;
    public float cameraDistance = 3.5f;
    public bool invertY = false;

    [Header("Movement")]
    public float walkSpeed = 5f;
    public float sprintSpeed = 8.5f;
    public float jumpForce = 7f;

    [Header("Graphics")]
    [Range(30, 144)] public int targetFrameRate = 60;
    public bool vSync = false;

    public void Apply()
    {
        Application.targetFrameRate = targetFrameRate;
        QualitySettings.vSyncCount = vSync ? 1 : 0;
    }
}
