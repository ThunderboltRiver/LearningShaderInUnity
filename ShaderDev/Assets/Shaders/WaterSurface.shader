// ==============================================================
// WaterSurface.shader
// URP（Universal Render Pipeline）対応 水面シェーダー
//
// 学習目的で作られた水面シェーダーです。
// 以下の6つのステップで段階的に機能を追加しています：
//   Step 1: 基本的な水の色（浅い・深い色のグラデーション）
//   Step 2: UVスクロールによる水の流れ表現
//   Step 3: 頂点シェーダーによる波の上下動
//   Step 4: ノーマルマップによる水面のリップル（細かい波紋）
//   Step 5: フレネル効果（視線の角度で色が変化）
//   Step 6: Depthベースのフォームライン（波の泡）
// ==============================================================
Shader "Custom/WaterSurface"
{
    // ----------------------------------------------------------------
    // Properties ブロック
    // Unityのインスペクターから調整できるパラメータをここに定義します。
    // ----------------------------------------------------------------
    Properties
    {
        // --- Step 1: 水の基本色 ---
        // 浅い部分の色（水面に近いほど明るく見える）
        _ShallowColor   ("Shallow Color",   Color)  = (0.3, 0.7, 0.9, 0.6)
        // 深い部分の色（水深が深いほど暗く沈んだ色に見える）
        _DeepColor      ("Deep Color",      Color)  = (0.05, 0.2, 0.5, 0.9)

        // --- Step 2: 水の流れ（UVスクロール） ---
        // 水が流れる速さ（大きいほど速く流れる）
        _FlowSpeed      ("Flow Speed",      Float)  = 0.3
        // 水が流れる方向（X=横方向, Y=縦方向）。正規化ベクトルを想定
        _FlowDirection  ("Flow Direction",  Vector) = (1.0, 0.5, 0.0, 0.0)

        // --- Step 3: 頂点波動 ---
        // 波の高さ（頂点がどれだけ上下するか）
        _WaveHeight     ("Wave Height",     Float)  = 0.1
        // 波の周波数（値が大きいほど波が細かくなる）
        _WaveFrequency  ("Wave Frequency",  Float)  = 2.0
        // 波のアニメーション速度（大きいほど波が速く動く）
        _WaveSpeed      ("Wave Speed",      Float)  = 1.5

        // --- Step 4: ノーマルマップ ---
        // 水面の細かい凹凸を表現するノーマルマップテクスチャ
        [Normal] _NormalMap     ("Normal Map",      2D)     = "bump" {}
        // ノーマルマップの強度（0=平坦, 1=通常, 2以上=誇張）
        _NormalStrength ("Normal Strength", Float)  = 1.0

        // --- Step 5: フレネル効果 ---
        // フレネル効果の強さ（大きいほど端が明るく光る）
        // フレネル効果：水面を正面から見ると透明だが、斜めから見ると反射して白く見える現象
        _FresnelPower   ("Fresnel Power",   Float)  = 3.0

        // --- Step 6: フォームライン（泡） ---
        // 波の泡の色
        _FoamColor      ("Foam Color",      Color)  = (1.0, 1.0, 1.0, 1.0)
        // 泡が表示される深度の閾値（大きいほど泡の範囲が広がる）
        _FoamThreshold  ("Foam Threshold",  Float)  = 0.3
    }

    // ----------------------------------------------------------------
    // SubShader ブロック
    // 実際のレンダリング設定とシェーダーコードを記述します。
    // ----------------------------------------------------------------
    SubShader
    {
        // RenderType: Transparent → 半透明オブジェクトとして扱う
        // Queue: Transparent    → 不透明オブジェクトの後に描画される
        // RenderPipeline: UniversalPipeline → URPでのみ使用
        Tags
        {
            "RenderType"      = "Transparent"
            "Queue"           = "Transparent"
            "RenderPipeline"  = "UniversalPipeline"
            "IgnoreProjector" = "True"
        }

        // 半透明合成：SrcAlpha と OneMinusSrcAlpha でアルファブレンディング
        // （アルファ値に応じて背景と合成する標準的な半透明処理）
        Blend SrcAlpha OneMinusSrcAlpha

        // ZWrite Off: 透明物体の深度書き込みを無効化
        // （深度バッファへの書き込みをしないことで、後ろのオブジェクトが正しく描画される）
        ZWrite Off

        // カリング: 両面描画（水面を裏からも見えるようにする）
        Cull Off

        // ----------------------------------------------------------------
        // Pass ブロック
        // URPのUniversalForwardパスを使用します。
        // ----------------------------------------------------------------
        Pass
        {
            // URPのフォワードレンダリングパス名（必須）
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            // 頂点シェーダーと フラグメントシェーダーのエントリーポイントを宣言
            #pragma vertex   vert
            #pragma fragment frag

            // URPの標準ライブラリをインクルード（座標変換・ライティング関数が含まれている）
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // Depth テクスチャ取得のために DeclareDepthTexture をインクルード
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            // ============================================================
            // CBUFFER: GPU に送るマテリアルプロパティのバッファ
            // SRP Batcher（バッチング最適化）に対応するため CBUFFER_START/END で囲む
            // ============================================================
            CBUFFER_START(UnityPerMaterial)
                // Step 1
                half4   _ShallowColor;
                half4   _DeepColor;
                // Step 2
                float   _FlowSpeed;
                float4  _FlowDirection;
                // Step 3
                float   _WaveHeight;
                float   _WaveFrequency;
                float   _WaveSpeed;
                // Step 4
                float4  _NormalMap_ST;   // テクスチャのTiling/Offsetを格納（Unity規約）
                float   _NormalStrength;
                // Step 5
                float   _FresnelPower;
                // Step 6
                half4   _FoamColor;
                float   _FoamThreshold;
            CBUFFER_END

            // ノーマルマップテクスチャと対応するサンプラー
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            // ============================================================
            // 頂点シェーダーへの入力構造体（メッシュから渡されるデータ）
            // ============================================================
            struct Attributes
            {
                float4 positionOS   : POSITION;  // オブジェクト空間の頂点座標
                float2 uv           : TEXCOORD0; // UV座標（テクスチャマッピング用）
                float3 normalOS     : NORMAL;    // オブジェクト空間の法線ベクトル
            };

            // ============================================================
            // 頂点シェーダーからフラグメントシェーダーへ渡すデータ
            // ============================================================
            struct Varyings
            {
                float4 positionHCS  : SV_POSITION; // クリップ空間の頂点座標（必須）
                float2 uv           : TEXCOORD0;   // テクスチャUV座標
                float3 positionWS   : TEXCOORD1;   // ワールド空間の頂点座標（フレネル計算に使用）
                float3 normalWS     : TEXCOORD2;   // ワールド空間の法線（フレネル計算に使用）
                float4 screenPos    : TEXCOORD3;   // スクリーン空間座標（Depth取得に使用）
            };

            // ============================================================
            // 頂点シェーダー
            // 各頂点の位置・法線・UVを計算してフラグメントシェーダーに渡す
            // ============================================================
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // ----------------------------------------------------------
                // Step 3: sin(_Time) を使った波の上下動
                // ----------------------------------------------------------
                // _Time.y は「ゲーム開始からの経過時間（秒）」
                // sin() は -1 〜 +1 の値を返す波形関数
                // 頂点のXZ座標と周波数・速度を組み合わせることで、
                // 水面全体が自然な波形に揺れるようになる

                // 波の位相：頂点のX・Z座標で位相をずらすことで「空間的な波」を作る
                float wavePhase = (IN.positionOS.x + IN.positionOS.z) * _WaveFrequency
                                  + _Time.y * _WaveSpeed;

                // sin 関数で -1〜+1 の上下運動を生成し、_WaveHeight でスケール
                float waveOffset = sin(wavePhase) * _WaveHeight;

                // 頂点のY（高さ）方向にオフセットを加算して波を表現
                float4 posOS = IN.positionOS;
                posOS.y += waveOffset;

                // ----------------------------------------------------------
                // 座標変換（オブジェクト空間 → ワールド空間 → クリップ空間）
                // TransformObjectToHClip: Unity URP の組み込み関数
                // ----------------------------------------------------------
                OUT.positionHCS = TransformObjectToHClip(posOS.xyz);

                // ワールド空間の座標（フレネル計算とDepth計算に必要）
                OUT.positionWS = TransformObjectToWorld(posOS.xyz);

                // ワールド空間の法線（フレネル計算に使用）
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                // UV 座標をそのまま渡す（フラグメントシェーダーでスクロールさせる）
                OUT.uv = IN.uv;

                // スクリーン空間の座標（Depthテクスチャのサンプリングに必要）
                OUT.screenPos = ComputeScreenPos(OUT.positionHCS);

                return OUT;
            }

            // ============================================================
            // フラグメントシェーダー
            // 各ピクセルの色を計算して出力する
            // ============================================================
            half4 frag(Varyings IN) : SV_Target
            {
                // ----------------------------------------------------------
                // Step 2: UVスクロールで水の流れを表現
                // ----------------------------------------------------------
                // _Time.y（経過時間）× _FlowSpeed × 流れ方向 を UV に加算することで
                // テクスチャが少しずつズレていき「流れている」ように見える

                // 流れ方向ベクトルの XY 成分だけを使う（ZW は不使用）
                float2 flowDir = _FlowDirection.xy;

                // 流れを2レイヤー重ねることで、より自然な水面を表現
                // レイヤー1: そのまま流す
                float2 uv1 = IN.uv + flowDir * _FlowSpeed * _Time.y;
                // レイヤー2: 少し遅く、逆方向に流す（複雑さを出す）
                float2 uv2 = IN.uv - flowDir * _FlowSpeed * 0.4 * _Time.y;

                // ----------------------------------------------------------
                // Step 4: ノーマルマップで細かいリップル（波紋）を表現
                // ----------------------------------------------------------
                // TRANSFORM_TEX: Tiling と Offset を適用してUVを変換するURP標準マクロ
                float2 normalUV1 = TRANSFORM_TEX(uv1, _NormalMap);
                float2 normalUV2 = TRANSFORM_TEX(uv2, _NormalMap);

                // ノーマルマップをサンプリング（2レイヤー）
                // UnpackNormal: テクスチャから法線ベクトルを復元する関数
                //   ノーマルマップは (R,G,B) → (X,Y,Z) の法線ベクトルとして格納されている
                float3 normal1 = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV1),
                    _NormalStrength
                );
                float3 normal2 = UnpackNormalScale(
                    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV2),
                    _NormalStrength
                );

                // 2レイヤーのノーマルを平均して合成
                float3 normalTS = normalize(normal1 + normal2);

                // タンジェント空間のノーマルをワールド空間に変換（近似: Plane水平のため）
                // 厳密にはTBN行列が必要だが、Plane面なら法線は上向き（0,1,0）なので近似可
                float3 perturbedNormalWS = normalize(IN.normalWS + float3(normalTS.x, 0.0, normalTS.y));

                // ----------------------------------------------------------
                // Step 5: フレネル効果
                // ----------------------------------------------------------
                // フレネル効果とは：
                //   水面を真正面から見ると透明（屈折が強い）
                //   斜めから見ると白く輝く（反射が強い）
                // という光学的な現象をシミュレートします。
                //
                // 計算式：fresnel = (1 - dot(N, V))^FresnelPower
                //   N = 法線ベクトル（水面の向き）
                //   V = 視線ベクトル（カメラから頂点への方向）
                //   dot(N,V) が 1 に近い（正面から）→ fresnel ≈ 0（透明寄り）
                //   dot(N,V) が 0 に近い（斜めから）→ fresnel ≈ 1（反射・白色寄り）

                // カメラ位置からピクセル位置に向かう正規化ベクトル
                float3 viewDir = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // 法線と視線の内積（正面向き=1, 真横=0）
                float NdotV = saturate(dot(perturbedNormalWS, viewDir));

                // フレネル係数（pow で非線形にする）
                float fresnel = pow(1.0 - NdotV, _FresnelPower);

                // ----------------------------------------------------------
                // Step 1: 基本的な水の色（浅い色と深い色のブレンド）
                // ----------------------------------------------------------
                // fresnel が大きい（斜め視点）→ DeepColor 寄り（より深く見える）
                // fresnel が小さい（正面視点）→ ShallowColor 寄り（浅く明るく見える）
                half4 waterColor = lerp(_ShallowColor, _DeepColor, fresnel);

                // ----------------------------------------------------------
                // Step 6: Depth-based フォームライン（波の泡）
                // ----------------------------------------------------------
                // 水面と背後のオブジェクト（例：水底、岸辺）の深度差を計算し、
                // 浅い部分（差が小さい）に白い泡（フォーム）を描画します。
                //
                // 手順：
                //   1. スクリーン座標から深度テクスチャをサンプリング（背後のオブジェクトの深度）
                //   2. 水面自体のデバイス深度を取得
                //   3. 両者の差がしきい値以下なら泡を表示

                // パースペクティブ補正したスクリーンUVを計算
                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;

                // 深度テクスチャから背後のオブジェクトの深度を取得
                float sceneDepth = SampleSceneDepth(screenUV);

                // デバイス深度をリニア（0=カメラ近, 1=カメラ遠）な深度に変換
                float sceneLinearDepth  = LinearEyeDepth(sceneDepth, _ZBufferParams);
                float waterLinearDepth  = IN.screenPos.w; // w = カメラからの距離（eye depth）

                // 水面と背後オブジェクトの深度差
                float depthDiff = sceneLinearDepth - waterLinearDepth;

                // 深度差がしきい値より小さい → 浅い部分 → 泡を表示
                // smoothstep(0, threshold, x): x が 0→threshold の間で 0→1 に滑らかに変化
                float foamMask = 1.0 - smoothstep(0.0, _FoamThreshold, depthDiff);

                // 泡の色を水面色に合成（フォームマスクで lerp）
                half4 finalColor = lerp(waterColor, _FoamColor, foamMask * _FoamColor.a);

                // ----------------------------------------------------------
                // 最終的なアルファ値の調整
                // ----------------------------------------------------------
                // フレネル効果でアルファも変化させる（斜め視点では不透明に近く）
                finalColor.a = lerp(_ShallowColor.a, _DeepColor.a, fresnel);
                // 泡の部分は完全に不透明に近い
                finalColor.a = max(finalColor.a, foamMask * _FoamColor.a);

                return finalColor;
            }

            ENDHLSL
        }
    }

    // フォールバック: このシェーダーが使用できない場合は隠す
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
