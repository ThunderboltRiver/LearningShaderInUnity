using UnityEngine;

/// <summary>
/// WaterController
/// 水面シェーダー（WaterSurface.shader）をインスペクターから
/// リアルタイムに操作するためのコントローラースクリプト。
///
/// 使い方：
///   1. Plane オブジェクトにこのスクリプトをアタッチする
///   2. Plane の MeshRenderer に WaterSurface マテリアルを設定する
///   3. インスペクターのスライダーで各パラメータを調整する
/// </summary>
[RequireComponent(typeof(MeshRenderer))]
public class WaterController : MonoBehaviour
{
    // ================================================================
    // インスペクター設定: 水の色
    // ================================================================

    [Header("水の色")]

    /// <summary>浅い部分の色（水面直下の明るい色）</summary>
    [Tooltip("水の浅い部分に適用される色です。")]
    public Color shallowColor = new Color(0.3f, 0.7f, 0.9f, 0.6f);

    /// <summary>深い部分の色（水深が深くなるほど暗く沈んだ色）</summary>
    [Tooltip("水の深い部分に適用される色です。")]
    public Color deepColor = new Color(0.05f, 0.2f, 0.5f, 0.9f);

    // ================================================================
    // インスペクター設定: 水の流れ（UVスクロール）
    // ================================================================

    [Header("水の流れ")]

    /// <summary>水が流れる速さ。大きいほど速く流れる。</summary>
    [Range(0f, 2f)]
    [Tooltip("UVスクロールの速度です。0=静止、2=非常に速い。")]
    public float flowSpeed = 0.3f;

    /// <summary>水が流れる方向（2Dベクトル）。正規化不要。</summary>
    [Tooltip("水の流れる方向を XY の2Dベクトルで指定します。")]
    public Vector2 flowDirection = new Vector2(1f, 0.5f);

    // ================================================================
    // インスペクター設定: 波の動き
    // ================================================================

    [Header("波の動き")]

    /// <summary>波の高さ（頂点が上下する量）</summary>
    [Range(0f, 1f)]
    [Tooltip("波の振幅（高さ）です。0=波なし、1=大きな波。")]
    public float waveHeight = 0.1f;

    /// <summary>波の周波数（細かさ）。大きいほど細かい波になる。</summary>
    [Range(0f, 10f)]
    [Tooltip("波の細かさ（周波数）です。大きいほど細かい波になります。")]
    public float waveFrequency = 2f;

    /// <summary>波のアニメーション速度</summary>
    [Range(0f, 5f)]
    [Tooltip("波が動く速さです。")]
    public float waveSpeed = 1.5f;

    // ================================================================
    // インスペクター設定: ノーマルマップ
    // ================================================================

    [Header("ノーマルマップ（細かい波紋）")]

    /// <summary>
    /// 水面の細かいリップル（波紋）を表現するノーマルマップテクスチャ。
    /// 未設定の場合はデフォルトのフラット法線が使われます。
    /// </summary>
    [Tooltip("水面の細かい凹凸を表現するノーマルマップです。未設定でも動作します。")]
    public Texture2D normalMap;

    /// <summary>ノーマルマップの強度。0=平坦、1=通常、2以上=誇張</summary>
    [Range(0f, 3f)]
    [Tooltip("ノーマルマップの強度です。0で完全に平坦になります。")]
    public float normalStrength = 1f;

    // ================================================================
    // インスペクター設定: フレネル効果
    // ================================================================

    [Header("フレネル効果")]

    /// <summary>
    /// フレネル効果の強さ。
    /// 大きいほど、斜めから見た時の反射（白っぽい輝き）が強くなる。
    /// </summary>
    [Range(0.1f, 10f)]
    [Tooltip("フレネル効果の強さです。大きいほど端が輝きます。")]
    public float fresnelPower = 3f;

    // ================================================================
    // インスペクター設定: フォームライン（泡）
    // ================================================================

    [Header("フォームライン（波の泡）")]

    /// <summary>波の泡の色</summary>
    [Tooltip("波の際に現れる泡の色です。")]
    public Color foamColor = Color.white;

    /// <summary>
    /// 泡が表示される深度の閾値。
    /// 大きいほど泡の表示範囲が広がる（水深の浅い部分）。
    /// </summary>
    [Range(0f, 2f)]
    [Tooltip("泡が表れる深度の範囲です。大きいほど広い範囲に泡が表れます。")]
    public float foamThreshold = 0.3f;

    // ================================================================
    // プライベートフィールド
    // ================================================================

    /// <summary>このオブジェクトに設定されたマテリアルへの参照</summary>
    private Material _material;

    // シェーダープロパティ名を事前にハッシュ化しておくことで、
    // 毎フレームの文字列検索コストを削減できます（パフォーマンス最適化）
    private static readonly int PropShallowColor   = Shader.PropertyToID("_ShallowColor");
    private static readonly int PropDeepColor      = Shader.PropertyToID("_DeepColor");
    private static readonly int PropFlowSpeed      = Shader.PropertyToID("_FlowSpeed");
    private static readonly int PropFlowDirection  = Shader.PropertyToID("_FlowDirection");
    private static readonly int PropWaveHeight     = Shader.PropertyToID("_WaveHeight");
    private static readonly int PropWaveFrequency  = Shader.PropertyToID("_WaveFrequency");
    private static readonly int PropWaveSpeed      = Shader.PropertyToID("_WaveSpeed");
    private static readonly int PropNormalMap      = Shader.PropertyToID("_NormalMap");
    private static readonly int PropNormalStrength = Shader.PropertyToID("_NormalStrength");
    private static readonly int PropFresnelPower   = Shader.PropertyToID("_FresnelPower");
    private static readonly int PropFoamColor      = Shader.PropertyToID("_FoamColor");
    private static readonly int PropFoamThreshold  = Shader.PropertyToID("_FoamThreshold");

    // ================================================================
    // Unityライフサイクルメソッド
    // ================================================================

    /// <summary>
    /// Start: ゲーム開始時に一度だけ呼ばれる。
    /// MeshRenderer からマテリアルの参照を取得する。
    /// </summary>
    private void Start()
    {
        // GetComponent で MeshRenderer を取得し、そのマテリアルを取得
        // .material はインスタンスを返すため、このオブジェクト固有の設定が可能になる
        MeshRenderer meshRenderer = GetComponent<MeshRenderer>();
        if (meshRenderer != null)
        {
            _material = meshRenderer.material;
        }
        else
        {
            Debug.LogWarning("[WaterController] MeshRenderer が見つかりません。");
        }

        // 初期値をマテリアルに反映
        ApplyToMaterial();
    }

    /// <summary>
    /// Update: 毎フレーム呼ばれる。
    /// インスペクターで変更されたパラメータをマテリアルに反映する。
    /// </summary>
    private void Update()
    {
        ApplyToMaterial();
    }

    // ================================================================
    // プライベートメソッド
    // ================================================================

    /// <summary>
    /// 現在のフィールド値をマテリアルのシェーダープロパティに書き込む。
    /// </summary>
    private void ApplyToMaterial()
    {
        // マテリアルが設定されていない場合は何もしない
        if (_material == null) return;

        // --- Step 1: 水の色を設定 ---
        _material.SetColor(PropShallowColor,   shallowColor);
        _material.SetColor(PropDeepColor,      deepColor);

        // --- Step 2: 水の流れを設定 ---
        _material.SetFloat(PropFlowSpeed,      flowSpeed);
        // Vector2 を Vector4 に変換して渡す（シェーダー側は float4）
        _material.SetVector(PropFlowDirection, new Vector4(flowDirection.x, flowDirection.y, 0f, 0f));

        // --- Step 3: 波の動きを設定 ---
        _material.SetFloat(PropWaveHeight,     waveHeight);
        _material.SetFloat(PropWaveFrequency,  waveFrequency);
        _material.SetFloat(PropWaveSpeed,      waveSpeed);

        // --- Step 4: ノーマルマップを設定 ---
        if (normalMap != null)
        {
            _material.SetTexture(PropNormalMap, normalMap);
        }
        _material.SetFloat(PropNormalStrength, normalStrength);

        // --- Step 5: フレネル効果を設定 ---
        _material.SetFloat(PropFresnelPower,   fresnelPower);

        // --- Step 6: フォームラインを設定 ---
        _material.SetColor(PropFoamColor,      foamColor);
        _material.SetFloat(PropFoamThreshold,  foamThreshold);
    }

    /// <summary>
    /// OnDestroy: オブジェクト破棄時に呼ばれる。
    /// .material でインスタンス化したマテリアルを解放する。
    /// </summary>
    private void OnDestroy()
    {
        // .material で生成されたインスタンスは手動で破棄しないとメモリリークになる
        if (_material != null)
        {
            Destroy(_material);
        }
    }
}
