# 水面シェーダー 学習ガイド 🌊

`WaterSurface.shader` と `WaterController.cs` を使って、Unity（URP）で水面を表現する方法を解説します。

---

## 目次

1. [シーンのセットアップ手順](#1-シーンのセットアップ手順)
2. [シェーダーパラメータ一覧](#2-シェーダーパラメータ一覧)
3. [実装テクニックの解説](#3-実装テクニックの解説)
   - [Step 1: 基本的な水の色](#step-1-基本的な水の色)
   - [Step 2: UVスクロール](#step-2-uvスクロール)
   - [Step 3: sin(_Time) で波を作る](#step-3-sin_time-で波を作る)
   - [Step 4: ノーマルマップの役割](#step-4-ノーマルマップの役割)
   - [Step 5: フレネル効果の数学的な意味](#step-5-フレネル効果の数学的な意味)
   - [Step 6: Depthベースのフォームライン](#step-6-depthベースのフォームライン)
4. [発展課題（次のステップ）](#4-発展課題次のステップ)

---

## 1. シーンのセットアップ手順

### 1-1. Plane を作成する

1. Unity エディターを開き、`ShaderDev` プロジェクトをロードする
2. **Hierarchy（ヒエラルキー）** ウィンドウで右クリック
3. **3D Object → Plane** を選択
4. Plane の名前を `WaterSurface` に変更（任意）
5. Transform を設定：
   - Position: `(0, 0, 0)`
   - Rotation: `(0, 0, 0)`
   - Scale: `(5, 1, 5)` などお好みで

> 💡 Plane はデフォルトで 10×10 ユニットのサイズです。Scale で拡大できます。

---

### 1-2. マテリアルを作成する

1. **Project ウィンドウ** で `Assets/Shaders/` フォルダを右クリック
2. **Create → Material** を選択
3. マテリアル名を `WaterSurface` に変更
4. Inspector でマテリアルを選択し、**Shader** ドロップダウンから
   `Custom/WaterSurface` を選択

---

### 1-3. マテリアルを Plane に適用する

1. Project ウィンドウで作成した `WaterSurface` マテリアルを選択
2. Hierarchy の `WaterSurface`（Plane）にドラッグ＆ドロップ

または

1. Hierarchy で `WaterSurface`（Plane）を選択
2. Inspector の **MeshRenderer → Materials** の Element 0 に  
   `WaterSurface` マテリアルをアサイン

---

### 1-4. WaterController スクリプトをアタッチする（オプション）

実行中にパラメータをリアルタイム調整したい場合：

1. Hierarchy で `WaterSurface`（Plane）を選択
2. Inspector で **Add Component** をクリック
3. `WaterController` を検索して追加
4. Play モードに入ると、Inspector のスライダーでリアルタイム調整が可能

---

### 1-5. ノーマルマップを設定する（オプション）

ノーマルマップを使うと、より自然なリップル（波紋）が表現できます：

1. フリー素材サイトや Unity Asset Store から水面用ノーマルマップを入手
   （例: [Polyhaven - Normal Maps](https://polyhaven.com/)）
2. インポート設定で **Texture Type: Normal map** を選択
3. `WaterSurface` マテリアルの **Normal Map** スロットにテクスチャをアサイン

---

## 2. シェーダーパラメータ一覧

| パラメータ名 | 型 | デフォルト値 | 説明 |
|---|---|---|---|
| `_ShallowColor` | Color | (0.3, 0.7, 0.9, 0.6) | 浅い部分の水の色（青緑・半透明） |
| `_DeepColor` | Color | (0.05, 0.2, 0.5, 0.9) | 深い部分の水の色（濃い青・不透明寄り） |
| `_FlowSpeed` | Float | 0.3 | 水が流れる速さ（0=静止） |
| `_FlowDirection` | Vector | (1, 0.5, 0, 0) | 水の流れる方向（XY成分のみ使用） |
| `_WaveHeight` | Float | 0.1 | 波の高さ（頂点の上下幅） |
| `_WaveFrequency` | Float | 2.0 | 波の細かさ（大きいほど細かい波） |
| `_WaveSpeed` | Float | 1.5 | 波のアニメーション速度 |
| `_NormalMap` | Texture2D | (bump) | 水面ノーマルマップテクスチャ |
| `_NormalStrength` | Float | 1.0 | ノーマルマップの強度（0=平坦） |
| `_FresnelPower` | Float | 3.0 | フレネル効果の強さ（大=端が輝く） |
| `_FoamColor` | Color | White | 波の泡の色 |
| `_FoamThreshold` | Float | 0.3 | 泡が表れる深度の閾値 |

---

## 3. 実装テクニックの解説

### Step 1: 基本的な水の色

水の色は「浅い部分」と「深い部分」の2色を`lerp`（線形補間）で混ぜることで表現します。

```hlsl
// lerp(a, b, t) → t=0 で a, t=1 で b, 中間は混合
half4 waterColor = lerp(_ShallowColor, _DeepColor, fresnel);
```

浅い水は光が透過して明るく見え、深い水は光が吸収されて暗く見えます。  
ここでは Step 5 のフレネル係数（`fresnel`）を混合パラメータとして使っています。

---

### Step 2: UVスクロール

**UVスクロール**とは、テクスチャの座標（UV）を時間とともにずらすことで、  
テクスチャが「流れている」ように見せるテクニックです。

```hlsl
// _Time.y = ゲーム開始からの経過秒数
// UV に（方向 × 速度 × 時間）を足すことで、毎フレーム少しずつずれる
float2 uv1 = IN.uv + flowDir * _FlowSpeed * _Time.y;
```

**なぜ2レイヤーにするのか？**  
1レイヤーだけだと動きが単調です。2つ目のレイヤーを逆方向・異なる速度で重ねることで、  
自然界の水面のような不規則なゆらぎを表現できます。

```hlsl
float2 uv2 = IN.uv - flowDir * _FlowSpeed * 0.4 * _Time.y;  // 逆方向・遅い
```

---

### Step 3: sin(_Time) で波を作る

`sin()` は -1〜+1 を周期的に繰り返す関数です。  
これを使って頂点の Y 座標（高さ）を上下させることで、波を表現します。

```
時間 ──→
  1 |  *       *       *
  0 |*   *   *   *   *   *
 -1 |      *       *
```

```hlsl
// 頂点の X・Z 座標を周波数でスケールし、時間をアニメーションに使う
float wavePhase = (IN.positionOS.x + IN.positionOS.z) * _WaveFrequency
                  + _Time.y * _WaveSpeed;

// sin で -1〜+1 の波形を生成し、_WaveHeight で高さをスケール
float waveOffset = sin(wavePhase) * _WaveHeight;

// 頂点の高さに加算
posOS.y += waveOffset;
```

**ポイント：**  
- `_WaveFrequency` が大きいほど波が細かく（高周波）なります
- `_WaveSpeed` が大きいほど波が速く動きます
- 複数の `sin()` を異なる周波数・位相で重ねると、より複雑な波が作れます（ガースタナー波など）

---

### Step 4: ノーマルマップの役割

**ノーマルマップ**とは、表面の微細な凹凸の「向き（法線ベクトル）」を  
テクスチャに焼き付けたものです。実際にメッシュを変形させなくても、  
光の計算に使う法線を変えることで、細かい凹凸があるように見せられます。

```hlsl
// テクスチャから法線ベクトルを取得（-1〜+1 の範囲に変換される）
float3 normal1 = UnpackNormalScale(
    SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, normalUV1),
    _NormalStrength  // 強度で凹凸を誇張/抑制
);
```

**UVスクロールとの組み合わせ：**  
ノーマルマップを UVスクロールした UV でサンプリングすることで、  
リップル（細かい波紋）がゆらゆらと動いて見えます。

---

### Step 5: フレネル効果の数学的な意味

**フレネル効果（Fresnel Effect）**は、光の反射率が入射角によって変わる物理現象です。

- 水面を**真上（正面）から見る** → 反射が少なく透明に見える
- 水面を**横（斜め）から見る** → 反射が強く白く輝く

これは日常でも経験できます。プールの端から底を見ると透明に見えますが、  
遠くから水平方向に見ると水面が光っています。

**計算式：**

```hlsl
// N = 法線ベクトル（水面の向き）
// V = 視線ベクトル（カメラから見た方向）
// dot(N, V) = 内積（正面なら 1、横なら 0 に近づく）

float NdotV = saturate(dot(perturbedNormalWS, viewDir));

// 1 - NdotV → 正面=0, 横=1
// pow() で非線形にすることで、端に近いほど急に輝く
float fresnel = pow(1.0 - NdotV, _FresnelPower);
```

**`_FresnelPower` の効果：**  
- 値が小さい（1〜2）: 緩やかなグラデーション
- 値が大きい（5〜10）: 端だけが急に輝くシャープな効果

---

### Step 6: Depthベースのフォームライン

**フォームライン（Foam Line）**とは、波が岸や障害物に当たる際に生まれる白い泡のラインです。

**仕組み：**  
1. **深度テクスチャ（Depth Texture）** から背後のオブジェクトの深度を読み取る
2. 水面自体の深度と比較して「差」を求める
3. 差が小さい（= 背後のオブジェクトと水面が近い = 浅い場所）に泡を表示

```hlsl
// 背後のオブジェクト（水底など）の深度
float sceneLinearDepth = LinearEyeDepth(sceneDepth, _ZBufferParams);
// 水面の深度
float waterLinearDepth = IN.screenPos.w;

// 差が小さいほど泡マスクが大きくなる
float depthDiff = sceneLinearDepth - waterLinearDepth;
float foamMask = 1.0 - smoothstep(0.0, _FoamThreshold, depthDiff);
```

**`smoothstep(a, b, x)` とは：**  
- `x < a` → 0
- `x > b` → 1
- 間は滑らかな S字カーブで補間

これを反転させることで、浅い部分（差が小さい）ほど泡が濃く、  
深い部分（差が大きい）ほど泡がないグラデーションになります。

> ⚠️ Depth Texture を使うには、URP の Renderer Settings で  
> **Depth Texture** を有効にする必要があります。  
> `Assets/Settings/PC_Renderer.asset` を選択し、  
> Inspector の **Depth Texture** チェックボックスをオンにしてください。

---

## 4. 発展課題（次のステップ）

### 🔷 Level 2: より本格的な水面へ

1. **複数の sin 波を重ねる（ガースタナー波）**  
   複数の周波数・方向の波を加算することで、より自然な波形を作れます。

2. **屈折（Refraction）**  
   水面の下が歪んで見える効果。URP では `_CameraOpaqueTexture`  
   （Opaque Texture）をサンプリングし、ノーマルオフセットをかけます。

3. **反射（Reflection）**  
   環境の反射。`Reflection Probe` や `Planar Reflection Camera` を  
   組み合わせることで、水面に空や周囲の物体が映り込みます。

---

### 🔶 Level 3: ダイナミックな表現へ

4. **インタラクティブな波紋**  
   プレイヤーや物体が水に触れた時に広がる波紋。  
   Render Texture + C# でリアルタイムに波紋テクスチャを更新します。

5. **パーティクルとの連携**  
   水しぶき・霧・水泡などを Particle System と組み合わせ、  
   水面エフェクトに立体感を加えます。

6. **Caustics（コースティクス）**  
   水中に光が差し込む際に床に映る揺らめく光のパターン。  
   プロシージャルなテクスチャや UV アニメーションで実装できます。

---

### 🔴 Level 4: 高度なシミュレーション

7. **FFT 波形シミュレーション**  
   海洋シミュレーション用の高精度な波形計算。  
   GPU Compute Shader を使い高速化します。

8. **Flow Map**  
   テクスチャに流れの方向を焼き付けた「フローマップ」を使い、  
   複雑な流れのパターン（渦・滝など）を表現します。

9. **Fluid Simulation（流体シミュレーション）**  
   Navier-Stokes 方程式を Compute Shader で解くことで、  
   リアルな液体の動きをリアルタイムシミュレートします。

---

## 参考資料

- [Unity URP Documentation](https://docs.unity3d.com/Packages/com.unity.render-pipelines.universal@latest)
- [The Book of Shaders](https://thebookofshaders.com/) — シェーダーの基礎を視覚的に学べる
- [Catlike Coding](https://catlikecoding.com/unity/tutorials/) — Unity シェーダーの詳細チュートリアル

---

Happy Shader Learning! 🚀
