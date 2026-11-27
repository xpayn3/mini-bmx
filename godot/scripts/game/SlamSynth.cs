using System;
using Godot;

/// Procedural landing slam, fitted to the user's recording of a bike hitting the ground (hit B of the
/// "mountain bike mayhem" clip, matched by WAVEFORM, not just spectrum): a low body that rings for ~100 ms
/// (30 damped sines, 60-585 Hz, fitted by matching pursuit: in the original they hold the first 12 ms
/// peak shape) plus a rattle: noise in three bands (450-1500, 1.5-5, 5-16 kHz) shaped by the recording's own
/// 1 ms loudness envelope, so the little bursts at ~20 / 42 / 70 ms are where they were. Render() makes one
/// 0.7 s mono 48 kHz hit; a seed + `vary` (0 = the recording, 0.3 = a clearly different bike) jitters the
/// body's pitches, decays, levels and the rattle's noise, so every slam is the same bike hitting the ground
/// a little differently. The fit comes from the scratch tool that ships with the research notes (see HANDOFF).
public partial class SlamSynth : RefCounted
{
	public const int RATE = 48000;
	private const float LEN = 0.7f;
	private const int STEP = 48;   // samples per envelope value (1 ms)
	// body atoms: freq Hz, decay 1/s, cos amp, sin amp
	private static readonly float[] Atoms = {
		66.284f, 35.000f, -0.04642f, 0.51419f,
		169.556f, 180.000f, 0.75912f, -0.35740f,
		177.612f, 10.000f, -0.05816f, 0.07527f,
		102.905f, 55.000f, -0.28272f, -0.26358f,
		51.270f, 35.000f, 0.14829f, -0.22289f,
		169.189f, 700.000f, -0.41701f, 0.31706f,
		169.189f, 10.000f, 0.01547f, -0.04399f,
		228.882f, 80.000f, -0.08162f, 0.13426f,
		194.458f, 10.000f, -0.04124f, 0.02785f,
		305.054f, 20.000f, 0.08095f, 0.06419f,
		76.172f, 20.000f, -0.06747f, 0.05266f,
		157.837f, 20.000f, 0.02502f, 0.06497f,
		182.373f, 10.000f, -0.00560f, -0.05296f,
		67.749f, 260.000f, -0.05764f, -0.23115f,
		228.882f, 10.000f, 0.01187f, 0.03128f,
		67.749f, 10.000f, 0.01592f, -0.02771f,
		96.313f, 10.000f, 0.02653f, -0.00398f,
		216.064f, 10.000f, -0.03701f, -0.00097f,
		123.047f, 35.000f, -0.00337f, -0.11092f,
		242.798f, 10.000f, -0.02660f, 0.02445f,
		154.541f, 35.000f, -0.02922f, 0.03108f,
		154.907f, 10.000f, -0.00550f, -0.01205f,
		274.658f, 20.000f, 0.00788f, 0.05913f,
		205.078f, 10.000f, 0.02508f, -0.00289f,
		291.504f, 10.000f, -0.00475f, -0.03637f,
		167.358f, 400.000f, -0.06491f, 0.12385f,
		167.358f, 10.000f, -0.00551f, -0.01056f,
		189.697f, 10.000f, 0.00863f, 0.02143f,
		179.077f, 20.000f, -0.01709f, 0.01754f,
		80.933f, 20.000f, -0.03182f, 0.02838f
	};
	private static readonly float[][] Env = {
		new[] { 0.04936f,0.14458f,0.16244f,0.04645f,0.07688f,0.07401f,0.07785f,0.09026f,0.06242f,0.03663f,0.04945f,0.02911f,0.03696f,0.03556f,0.03761f,0.03157f,0.03254f,0.06429f,0.09417f,0.09006f,0.04697f,0.04633f,0.07745f,0.05576f,0.08717f,0.09291f,0.03667f,0.05666f,0.04813f,0.06115f,0.05484f,0.05595f,0.03984f,0.03591f,0.02966f,0.04214f,0.06615f,0.04955f,0.04168f,0.03198f,0.02131f,0.03364f,0.02286f,0.02734f,0.03695f,0.02379f,0.01933f,0.00961f,0.02341f,0.06933f,0.04639f,0.03504f,0.04551f,0.02806f,0.04898f,0.04106f,0.03855f,0.04452f,0.02608f,0.01608f,0.03416f,0.03460f,0.02960f,0.02435f,0.02184f,0.04552f,0.02587f,0.04103f,0.01138f,0.02349f,0.01470f,0.03900f,0.04452f,0.02545f,0.02709f,0.03496f,0.02535f,0.03407f,0.01798f,0.03687f,0.01998f,0.01495f,0.02428f,0.02093f,0.02123f,0.00895f,0.02447f,0.03556f,0.03403f,0.01674f,0.01884f,0.02129f,0.01231f,0.02921f,0.04279f,0.01547f,0.01245f,0.01948f,0.01466f,0.00649f,0.01959f,0.01954f,0.02308f,0.01996f,0.02197f,0.00975f,0.01649f,0.01253f,0.00776f,0.01621f,0.01082f,0.00811f,0.00283f,0.01326f,0.01361f,0.01123f,0.00767f,0.01659f,0.01234f,0.01178f,0.00725f,0.00683f,0.01334f,0.00996f,0.00706f,0.01087f,0.00576f,0.00294f,0.00373f,0.00178f,0.00193f,0.00190f,0.00637f,0.01258f,0.00676f,0.00601f,0.00982f,0.00944f,0.00367f,0.00741f,0.00412f,0.00331f,0.00539f,0.00699f,0.01183f,0.00581f,0.00412f,0.00745f,0.01861f,0.01015f,0.00172f,0.00415f,0.00581f,0.01163f,0.01017f,0.01439f,0.01482f,0.01532f,0.00702f,0.00610f,0.00298f,0.00732f,0.01020f,0.00978f,0.00419f,0.00598f,0.00857f,0.00421f,0.00981f,0.00911f,0.00380f,0.00386f,0.01022f,0.01043f,0.01260f,0.00747f,0.00602f,0.00581f,0.00277f,0.00527f,0.00642f,0.00901f,0.00757f,0.00253f,0.00921f,0.00464f,0.00531f,0.00180f,0.00104f,0.00281f,0.00520f,0.00536f,0.00225f,0.00337f,0.00308f,0.00222f,0.00324f,0.00190f,0.00212f,0.00171f,0.00145f,0.00313f,0.00683f,0.00792f,0.00426f,0.00370f,0.00290f,0.00619f,0.00964f,0.00455f,0.00309f,0.00149f,0.00343f,0.00216f,0.00514f,0.00755f,0.00550f,0.00457f,0.00523f,0.00916f,0.00574f,0.00411f,0.00337f,0.00373f,0.00261f,0.00235f,0.00155f,0.00146f,0.00373f,0.00306f,0.00353f,0.00599f,0.00205f,0.00294f,0.00358f,0.00442f,0.00288f,0.00173f,0.00196f,0.00408f,0.00296f,0.00323f,0.00289f,0.00248f,0.00109f,0.00240f,0.00263f,0.00117f,0.00335f,0.00470f,0.00276f,0.00173f,0.00348f,0.00197f,0.00100f,0.00145f,0.00233f,0.00264f,0.00081f,0.00256f,0.00197f,0.00187f,0.00186f,0.00298f,0.00367f,0.00418f,0.00478f,0.00522f,0.00431f,0.00450f,0.00592f,0.00484f,0.00270f,0.00389f,0.00246f,0.00339f,0.00383f,0.00425f,0.00279f,0.00350f,0.00371f,0.00370f,0.00295f,0.00073f,0.00145f,0.00146f,0.00095f,0.00343f,0.00172f,0.00300f,0.00204f,0.00057f,0.00137f,0.00324f,0.00236f,0.00309f,0.00295f,0.00435f,0.00271f,0.00565f,0.00352f,0.00238f,0.00322f,0.00175f,0.00184f,0.00155f,0.00084f,0.00086f,0.00236f,0.00194f,0.00256f,0.00230f,0.00193f,0.00096f,0.00205f,0.00155f,0.00155f,0.00159f,0.00165f,0.00109f,0.00147f,0.00072f,0.00078f,0.00059f,0.00087f,0.00155f,0.00136f,0.00114f,0.00291f,0.00199f,0.00190f,0.00176f,0.00130f,0.00112f,0.00160f,0.00273f,0.00196f,0.00212f,0.00314f,0.00333f,0.00346f,0.00125f,0.00142f,0.00195f,0.00221f,0.00192f,0.00113f,0.00346f,0.00243f,0.00074f,0.00337f,0.00333f,0.00087f,0.00077f,0.00204f,0.00161f,0.00102f,0.00148f,0.00146f,0.00082f,0.00083f,0.00154f,0.00165f,0.00095f,0.00150f,0.00092f,0.00057f,0.00209f,0.00178f,0.00150f,0.00247f,0.00253f,0.00191f,0.00318f,0.00224f,0.00251f,0.00198f,0.00151f,0.00196f,0.00136f,0.00195f,0.00142f,0.00087f,0.00165f,0.00157f,0.00101f,0.00075f,0.00231f,0.00217f,0.00211f,0.00166f,0.00246f,0.00208f,0.00226f,0.00143f,0.00198f,0.00115f,0.00158f,0.00228f,0.00235f,0.00225f,0.00263f,0.00333f,0.00328f,0.00323f,0.00321f,0.00382f,0.01590f,0.01740f,0.01471f,0.01582f,0.00433f,0.01165f,0.01346f,0.01443f,0.00911f,0.00763f,0.00231f,0.00342f,0.00271f,0.00419f,0.00563f,0.00675f,0.00238f,0.00762f,0.00799f,0.00217f,0.00375f,0.00787f,0.00462f,0.00390f,0.00449f,0.00945f,0.01003f,0.00837f,0.00685f,0.00550f,0.00418f,0.00612f,0.01217f,0.00905f,0.00605f,0.00472f,0.00449f,0.00393f,0.00365f,0.00403f,0.00998f,0.00474f,0.00381f,0.00500f,0.00612f,0.00294f,0.00251f,0.00572f,0.00409f,0.00397f,0.00388f,0.00799f,0.00443f,0.00401f,0.00422f,0.00185f,0.00191f,0.00293f,0.00364f,0.00180f,0.00470f,0.00340f,0.00290f,0.00282f,0.00309f,0.00360f,0.00181f,0.00140f,0.00166f,0.00281f,0.00302f,0.00162f,0.00158f,0.00058f,0.00271f,0.00231f,0.00182f,0.00100f,0.00142f,0.00100f,0.00258f,0.00147f,0.00157f,0.00271f,0.00232f,0.00234f,0.00169f,0.00231f,0.00202f,0.00181f,0.00212f,0.00111f,0.00197f,0.00325f,0.00150f,0.00099f,0.00127f,0.00110f,0.00126f,0.00083f,0.00085f,0.00054f,0.00126f,0.00236f,0.00265f,0.00181f,0.00164f,0.00168f,0.00183f,0.00234f,0.00130f,0.00151f,0.00298f,0.00220f,0.00112f,0.00346f,0.00241f,0.00192f,0.00237f,0.00313f,0.00353f,0.00119f,0.00114f,0.00182f,0.00139f,0.00132f,0.00135f,0.00177f,0.00085f,0.00108f,0.00166f,0.00098f,0.00088f,0.00183f,0.00124f,0.00073f,0.00400f,0.00472f,0.00124f,0.00252f,0.00248f,0.00308f,0.00434f,0.00431f,0.00416f,0.00110f,0.00140f,0.00182f,0.00200f,0.00115f,0.00100f,0.00070f,0.00139f,0.00220f,0.00191f,0.00160f,0.00149f,0.00245f,0.00305f,0.00180f,0.00228f,0.00213f,0.00169f,0.00133f,0.00221f,0.00368f,0.00358f,0.00170f,0.00150f,0.00236f,0.00230f,0.00232f,0.00136f,0.00176f,0.00251f,0.00291f,0.00280f,0.00074f,0.00448f,0.00280f,0.00221f,0.00155f,0.00077f,0.00097f,0.00222f,0.00255f,0.00210f,0.00199f,0.00234f,0.00159f,0.00143f,0.00128f,0.00159f,0.00142f,0.00061f,0.00092f,0.00096f,0.00148f,0.00170f,0.00104f,0.00136f,0.00194f,0.00216f,0.00211f,0.00220f,0.00281f,0.00167f,0.00254f,0.00120f,0.00167f,0.00155f,0.00129f,0.00212f,0.00241f,0.00248f,0.00193f,0.00256f,0.00241f,0.00144f,0.00273f,0.00273f,0.00335f,0.00204f,0.00193f,0.00234f,0.00148f,0.00179f,0.00183f,0.00211f,0.00187f,0.00215f,0.00174f,0.00157f,0.00272f,0.00320f,0.00254f,0.00274f,0.00209f,0.00199f,0.00248f,0.00220f,0.00234f,0.00231f,0.00217f,0.00306f,0.00232f,0.00201f,0.00257f,0.00221f,0.00190f,0.00309f,0.00382f,0.00303f,0.00298f,0.00294f,0.00279f,0.00251f,0.00323f,0.00459f,0.00415f,0.00380f,0.00421f,0.00462f,0.00399f,0.00369f,0.00405f,0.00295f,0.00369f,0.00399f,0.00511f,0.00558f,0.00606f,0.00642f,0.00648f,0.00540f,0.00646f,0.00664f,0.00531f,0.00585f,0.00693f,0.00697f,0.00715f,0.00802f,0.00818f,0.00863f,0.00886f,0.01028f,0.01112f,0.01305f,0.01584f,0.01906f,0.02350f,0.03129f },
		new[] { 0.02002f,0.05723f,0.14399f,0.10703f,0.10453f,0.04688f,0.03996f,0.06018f,0.04091f,0.02839f,0.02859f,0.04842f,0.03649f,0.03986f,0.03209f,0.02075f,0.05997f,0.05500f,0.07512f,0.11581f,0.06358f,0.07565f,0.05447f,0.07680f,0.05318f,0.06675f,0.05558f,0.06081f,0.06327f,0.04362f,0.02814f,0.07157f,0.06006f,0.05512f,0.04628f,0.02078f,0.04166f,0.02664f,0.01973f,0.02579f,0.02718f,0.04189f,0.04755f,0.03729f,0.04322f,0.04230f,0.03319f,0.03748f,0.03739f,0.04705f,0.04673f,0.03135f,0.03735f,0.05255f,0.03798f,0.01672f,0.01549f,0.01919f,0.02186f,0.02630f,0.02393f,0.03172f,0.02006f,0.02203f,0.03387f,0.02326f,0.03766f,0.02891f,0.02959f,0.01867f,0.02605f,0.07886f,0.09402f,0.05514f,0.03262f,0.06667f,0.02504f,0.04103f,0.04215f,0.02229f,0.02363f,0.01803f,0.01789f,0.01541f,0.01910f,0.01359f,0.01777f,0.01547f,0.02104f,0.02343f,0.01365f,0.01439f,0.00994f,0.00655f,0.00657f,0.00694f,0.01091f,0.00889f,0.01212f,0.00674f,0.00506f,0.00861f,0.01027f,0.00769f,0.00520f,0.00836f,0.00651f,0.00770f,0.00621f,0.00776f,0.01243f,0.00684f,0.00791f,0.01282f,0.00727f,0.00482f,0.00431f,0.00575f,0.00576f,0.00825f,0.00794f,0.00752f,0.00745f,0.00577f,0.00477f,0.00587f,0.00410f,0.00369f,0.00774f,0.00702f,0.00801f,0.00406f,0.00498f,0.00668f,0.00614f,0.00658f,0.00272f,0.00474f,0.00411f,0.00374f,0.00349f,0.00872f,0.01035f,0.00897f,0.01599f,0.01031f,0.00674f,0.00687f,0.00488f,0.00555f,0.00825f,0.00842f,0.00960f,0.00796f,0.00660f,0.00596f,0.00325f,0.00619f,0.00527f,0.00766f,0.00306f,0.00308f,0.00350f,0.00423f,0.00361f,0.00328f,0.00379f,0.00180f,0.00389f,0.00302f,0.00203f,0.00377f,0.00333f,0.00236f,0.00385f,0.00219f,0.00175f,0.00254f,0.00138f,0.00215f,0.00344f,0.00355f,0.00267f,0.00223f,0.00293f,0.00215f,0.00273f,0.00256f,0.00202f,0.00163f,0.00152f,0.00272f,0.00235f,0.00354f,0.00367f,0.00221f,0.00204f,0.00165f,0.00154f,0.00273f,0.00266f,0.00494f,0.00291f,0.00314f,0.00329f,0.00384f,0.00281f,0.00267f,0.00171f,0.00316f,0.00250f,0.00222f,0.00176f,0.00190f,0.00244f,0.00167f,0.00209f,0.00181f,0.00199f,0.00263f,0.00191f,0.00127f,0.00152f,0.00132f,0.00171f,0.00141f,0.00166f,0.00176f,0.00132f,0.00126f,0.00151f,0.00088f,0.00123f,0.00067f,0.00049f,0.00118f,0.00168f,0.00158f,0.00111f,0.00103f,0.00106f,0.00064f,0.00105f,0.00080f,0.00081f,0.00072f,0.00120f,0.00099f,0.00128f,0.00077f,0.00092f,0.00083f,0.00060f,0.00075f,0.00098f,0.00042f,0.00100f,0.00104f,0.00094f,0.00072f,0.00060f,0.00086f,0.00064f,0.00070f,0.00094f,0.00091f,0.00082f,0.00047f,0.00053f,0.00051f,0.00082f,0.00058f,0.00115f,0.00123f,0.00095f,0.00097f,0.00069f,0.00077f,0.00090f,0.00068f,0.00082f,0.00054f,0.00043f,0.00044f,0.00051f,0.00049f,0.00060f,0.00057f,0.00045f,0.00063f,0.00056f,0.00055f,0.00036f,0.00038f,0.00054f,0.00069f,0.00040f,0.00036f,0.00054f,0.00099f,0.00067f,0.00059f,0.00081f,0.00061f,0.00033f,0.00032f,0.00024f,0.00039f,0.00058f,0.00063f,0.00046f,0.00084f,0.00115f,0.00053f,0.00049f,0.00057f,0.00046f,0.00067f,0.00078f,0.00071f,0.00060f,0.00038f,0.00043f,0.00046f,0.00064f,0.00083f,0.00084f,0.00097f,0.00071f,0.00103f,0.00091f,0.00040f,0.00087f,0.00061f,0.00067f,0.00066f,0.00090f,0.00056f,0.00055f,0.00053f,0.00075f,0.00082f,0.00069f,0.00082f,0.00080f,0.00064f,0.00049f,0.00041f,0.00046f,0.00067f,0.00062f,0.00041f,0.00048f,0.00069f,0.00070f,0.00097f,0.00068f,0.00068f,0.00052f,0.00034f,0.00038f,0.00058f,0.00046f,0.00036f,0.00035f,0.00051f,0.00050f,0.00082f,0.00067f,0.00046f,0.00043f,0.00040f,0.00060f,0.00084f,0.00048f,0.00057f,0.00081f,0.00043f,0.00073f,0.00078f,0.00043f,0.00040f,0.00037f,0.00053f,0.00034f,0.00046f,0.00034f,0.00049f,0.00054f,0.00060f,0.00037f,0.00058f,0.00060f,0.00044f,0.00053f,0.00053f,0.00051f,0.00062f,0.00064f,0.00075f,0.00121f,0.00075f,0.00100f,0.00096f,0.00168f,0.00169f,0.00271f,0.00657f,0.03070f,0.00870f,0.01651f,0.00441f,0.00210f,0.00299f,0.00368f,0.00430f,0.00356f,0.00380f,0.00386f,0.00479f,0.00452f,0.00683f,0.01148f,0.00469f,0.00832f,0.00415f,0.00453f,0.00235f,0.00280f,0.00251f,0.00428f,0.00835f,0.00746f,0.00706f,0.00542f,0.00240f,0.00609f,0.00195f,0.00183f,0.00378f,0.00225f,0.00350f,0.00264f,0.00193f,0.00210f,0.00264f,0.00186f,0.00147f,0.00239f,0.00201f,0.00232f,0.00269f,0.00183f,0.00190f,0.00167f,0.00261f,0.00231f,0.00580f,0.01291f,0.00714f,0.00553f,0.00466f,0.00446f,0.00239f,0.00198f,0.00188f,0.00185f,0.00213f,0.00161f,0.00051f,0.00053f,0.00079f,0.00148f,0.00209f,0.00178f,0.00095f,0.00159f,0.00150f,0.00187f,0.00126f,0.00151f,0.00115f,0.00109f,0.00138f,0.00191f,0.00181f,0.00106f,0.00116f,0.00144f,0.00125f,0.00087f,0.00210f,0.00136f,0.00171f,0.00176f,0.00149f,0.00068f,0.00140f,0.00153f,0.00125f,0.00098f,0.00137f,0.00085f,0.00038f,0.00077f,0.00053f,0.00045f,0.00089f,0.00108f,0.00138f,0.00360f,0.00307f,0.00174f,0.00198f,0.00100f,0.00065f,0.00060f,0.00078f,0.00067f,0.00076f,0.00177f,0.00080f,0.00068f,0.00047f,0.00083f,0.00108f,0.00063f,0.00055f,0.00055f,0.00070f,0.00057f,0.00062f,0.00072f,0.00067f,0.00143f,0.00052f,0.00052f,0.00057f,0.00069f,0.00061f,0.00099f,0.00068f,0.00082f,0.00074f,0.00209f,0.00112f,0.00068f,0.00100f,0.00328f,0.00286f,0.00074f,0.00081f,0.00086f,0.00084f,0.00076f,0.00081f,0.00079f,0.00048f,0.00039f,0.00217f,0.00165f,0.00125f,0.00151f,0.00208f,0.00553f,0.00591f,0.00216f,0.00303f,0.00172f,0.00167f,0.00119f,0.00242f,0.00095f,0.00088f,0.00096f,0.00113f,0.00105f,0.00053f,0.00064f,0.00134f,0.00144f,0.00088f,0.00060f,0.00120f,0.00073f,0.00083f,0.00080f,0.00094f,0.00070f,0.00067f,0.00057f,0.00075f,0.00109f,0.00064f,0.00066f,0.00066f,0.00091f,0.00067f,0.00138f,0.00087f,0.00047f,0.00089f,0.00094f,0.00112f,0.00108f,0.00107f,0.00070f,0.00095f,0.00108f,0.00081f,0.00064f,0.00050f,0.00063f,0.00079f,0.00053f,0.00081f,0.00115f,0.00088f,0.00118f,0.00465f,0.00508f,0.00177f,0.00199f,0.00172f,0.00234f,0.00185f,0.00090f,0.00087f,0.00067f,0.00044f,0.00032f,0.00049f,0.00069f,0.00078f,0.00053f,0.00106f,0.00095f,0.00070f,0.00089f,0.00061f,0.00043f,0.00078f,0.00041f,0.00050f,0.00083f,0.00072f,0.00040f,0.00035f,0.00039f,0.00054f,0.00044f,0.00073f,0.00062f,0.00048f,0.00041f,0.00127f,0.00117f,0.00093f,0.00058f,0.00067f,0.00064f,0.00052f,0.00203f,0.00088f,0.00071f,0.00067f,0.00069f,0.00061f,0.00077f,0.00081f,0.00102f,0.00088f,0.00093f,0.00100f,0.00094f,0.00120f,0.00128f,0.00110f,0.00132f,0.00225f,0.00233f,0.00100f,0.00190f,0.00238f,0.00222f,0.00241f,0.00264f,0.00157f,0.00177f,0.00228f,0.00255f,0.00290f,0.00373f,0.00403f,0.00445f,0.00516f,0.00614f,0.00749f,0.01003f,0.01330f },
		new[] { 0.00597f,0.04638f,0.06546f,0.02207f,0.03261f,0.01657f,0.02881f,0.04730f,0.01358f,0.01902f,0.02217f,0.01843f,0.01641f,0.02286f,0.03037f,0.02743f,0.02734f,0.02729f,0.05736f,0.09013f,0.11879f,0.04881f,0.05983f,0.07683f,0.04989f,0.05238f,0.04641f,0.04435f,0.05059f,0.04527f,0.02544f,0.02233f,0.02951f,0.03861f,0.02051f,0.02480f,0.04665f,0.03957f,0.02434f,0.04676f,0.03209f,0.20673f,0.12162f,0.08608f,0.04513f,0.03368f,0.03499f,0.03292f,0.02351f,0.03371f,0.04736f,0.03851f,0.05327f,0.03663f,0.04043f,0.01577f,0.02055f,0.03727f,0.04293f,0.06487f,0.05566f,0.04580f,0.06139f,0.04518f,0.04910f,0.07827f,0.03563f,0.04619f,0.04724f,0.04045f,0.08068f,0.08319f,0.09064f,0.05086f,0.03238f,0.04518f,0.05148f,0.05230f,0.02258f,0.01619f,0.02022f,0.01783f,0.00907f,0.01075f,0.00862f,0.01556f,0.02711f,0.02074f,0.02676f,0.02392f,0.01559f,0.01607f,0.01740f,0.01004f,0.00642f,0.00850f,0.00575f,0.00646f,0.00478f,0.01365f,0.01076f,0.01029f,0.00543f,0.01086f,0.00934f,0.01868f,0.03522f,0.02105f,0.02112f,0.01545f,0.01403f,0.00932f,0.00837f,0.01605f,0.01035f,0.00739f,0.00660f,0.00748f,0.00916f,0.00660f,0.00789f,0.01081f,0.01173f,0.00617f,0.00706f,0.00575f,0.01293f,0.01071f,0.01673f,0.01429f,0.01005f,0.01032f,0.00709f,0.00486f,0.00658f,0.00250f,0.00418f,0.00254f,0.00347f,0.00362f,0.00366f,0.02432f,0.00885f,0.01103f,0.00960f,0.00795f,0.00696f,0.00729f,0.00902f,0.00761f,0.00544f,0.01355f,0.01046f,0.00454f,0.00407f,0.00413f,0.00835f,0.00389f,0.00534f,0.02020f,0.00384f,0.00259f,0.00682f,0.01154f,0.00733f,0.00596f,0.00538f,0.00383f,0.00430f,0.00318f,0.00316f,0.00406f,0.00333f,0.00237f,0.00452f,0.00310f,0.00283f,0.00281f,0.00374f,0.00708f,0.00515f,0.00501f,0.00418f,0.00196f,0.00305f,0.00247f,0.00182f,0.00206f,0.00179f,0.00133f,0.00205f,0.00154f,0.00119f,0.00251f,0.00614f,0.00598f,0.00343f,0.00272f,0.00290f,0.00187f,0.00295f,0.03099f,0.01195f,0.00958f,0.00887f,0.00341f,0.00436f,0.00271f,0.00343f,0.00509f,0.00175f,0.00214f,0.00118f,0.00313f,0.00200f,0.00125f,0.00156f,0.00114f,0.00120f,0.00184f,0.00163f,0.00105f,0.00163f,0.00121f,0.00104f,0.00103f,0.00151f,0.00143f,0.00070f,0.00068f,0.00101f,0.00080f,0.00115f,0.00085f,0.00058f,0.00092f,0.00067f,0.00216f,0.00168f,0.00100f,0.00086f,0.00086f,0.00073f,0.00107f,0.00085f,0.00069f,0.00106f,0.00077f,0.00088f,0.00069f,0.00092f,0.00128f,0.00161f,0.00129f,0.00108f,0.00087f,0.00078f,0.00074f,0.00076f,0.00051f,0.00133f,0.00078f,0.00109f,0.00061f,0.00054f,0.00163f,0.00143f,0.00117f,0.00066f,0.00064f,0.00183f,0.00083f,0.00047f,0.00119f,0.00075f,0.00107f,0.00089f,0.00074f,0.00081f,0.00061f,0.00050f,0.00057f,0.00050f,0.00062f,0.00053f,0.00063f,0.00052f,0.00048f,0.00054f,0.00059f,0.00051f,0.00050f,0.00034f,0.00072f,0.00040f,0.00054f,0.00062f,0.00041f,0.00050f,0.00037f,0.00040f,0.00059f,0.00034f,0.00027f,0.00047f,0.00031f,0.00038f,0.00037f,0.00048f,0.00036f,0.00035f,0.00056f,0.00051f,0.00049f,0.00051f,0.00058f,0.00040f,0.00051f,0.00042f,0.00034f,0.00043f,0.00041f,0.00041f,0.00035f,0.00158f,0.00170f,0.00164f,0.00137f,0.00120f,0.00080f,0.00070f,0.00061f,0.00093f,0.00082f,0.00062f,0.00057f,0.00048f,0.00072f,0.00047f,0.00359f,0.00313f,0.00078f,0.00035f,0.00036f,0.00054f,0.00028f,0.00044f,0.00049f,0.00040f,0.00037f,0.00031f,0.00034f,0.00055f,0.00038f,0.00049f,0.00034f,0.00055f,0.00031f,0.00046f,0.00054f,0.00043f,0.00094f,0.00043f,0.00035f,0.00030f,0.00035f,0.00038f,0.00028f,0.00030f,0.00039f,0.00025f,0.00035f,0.00027f,0.00037f,0.00030f,0.00032f,0.00031f,0.00030f,0.00035f,0.00043f,0.00039f,0.00030f,0.00037f,0.00031f,0.00017f,0.00049f,0.00030f,0.00031f,0.00039f,0.00016f,0.00028f,0.00026f,0.00039f,0.00062f,0.00086f,0.00071f,0.00072f,0.00047f,0.00033f,0.00044f,0.00233f,0.00045f,0.00035f,0.00040f,0.00045f,0.00056f,0.00070f,0.00104f,0.00482f,0.00140f,0.00130f,0.00113f,0.00159f,0.00222f,0.00091f,0.00121f,0.00131f,0.00124f,0.00111f,0.00429f,0.00391f,0.00563f,0.00249f,0.00205f,0.00223f,0.00197f,0.00108f,0.00154f,0.00116f,0.00085f,0.00090f,0.00143f,0.00311f,0.00343f,0.01745f,0.00438f,0.00294f,0.00184f,0.00169f,0.00121f,0.00144f,0.00145f,0.00127f,0.00107f,0.00270f,0.00368f,0.00171f,0.00128f,0.00219f,0.00147f,0.00209f,0.00133f,0.00142f,0.00112f,0.00259f,0.00185f,0.00268f,0.00464f,0.00749f,0.00491f,0.00415f,0.00390f,0.00295f,0.00237f,0.00104f,0.00100f,0.00090f,0.00090f,0.00079f,0.00065f,0.00052f,0.00043f,0.00145f,0.00204f,0.00440f,0.00217f,0.00169f,0.00133f,0.00118f,0.00087f,0.00104f,0.00083f,0.00086f,0.00078f,0.00108f,0.00099f,0.00090f,0.00105f,0.00067f,0.00051f,0.00114f,0.00185f,0.00174f,0.00117f,0.00075f,0.00075f,0.00101f,0.00203f,0.00108f,0.00125f,0.00134f,0.00090f,0.00079f,0.00066f,0.00066f,0.00050f,0.00063f,0.00103f,0.00119f,0.00232f,0.00386f,0.00135f,0.00074f,0.00084f,0.00060f,0.00064f,0.00074f,0.00078f,0.00051f,0.00059f,0.00104f,0.00045f,0.00038f,0.00045f,0.00057f,0.00062f,0.00077f,0.00058f,0.00030f,0.00028f,0.00045f,0.00033f,0.00041f,0.00051f,0.00056f,0.00049f,0.00029f,0.00038f,0.00062f,0.00094f,0.00062f,0.00059f,0.00101f,0.00035f,0.00088f,0.00054f,0.00051f,0.00110f,0.00355f,0.00439f,0.00064f,0.00134f,0.00106f,0.00053f,0.00076f,0.00078f,0.00078f,0.00058f,0.00039f,0.00039f,0.00035f,0.00037f,0.00052f,0.00156f,0.00374f,0.00257f,0.00206f,0.00229f,0.00123f,0.00089f,0.00067f,0.00067f,0.00059f,0.00058f,0.00052f,0.00052f,0.00051f,0.00036f,0.00056f,0.00110f,0.00168f,0.00167f,0.00078f,0.00109f,0.00097f,0.00106f,0.00080f,0.00058f,0.00085f,0.00044f,0.00057f,0.00120f,0.00092f,0.00059f,0.00061f,0.00040f,0.00099f,0.00047f,0.00271f,0.00109f,0.00074f,0.00051f,0.00097f,0.00080f,0.00170f,0.00284f,0.00086f,0.00094f,0.00064f,0.00023f,0.00035f,0.00026f,0.00030f,0.00050f,0.00085f,0.00047f,0.00046f,0.00078f,0.00098f,0.00337f,0.00216f,0.00157f,0.00159f,0.00133f,0.00090f,0.00080f,0.00072f,0.00063f,0.00121f,0.00068f,0.00061f,0.00082f,0.00047f,0.00028f,0.00060f,0.00097f,0.00104f,0.00049f,0.00065f,0.00054f,0.00063f,0.00039f,0.00037f,0.00033f,0.00036f,0.00044f,0.00026f,0.00030f,0.00037f,0.00043f,0.00039f,0.00030f,0.00028f,0.00030f,0.00024f,0.00035f,0.00045f,0.00027f,0.00026f,0.00020f,0.00031f,0.00031f,0.00040f,0.00024f,0.00023f,0.00025f,0.00023f,0.00020f,0.00018f,0.00021f,0.00022f,0.00022f,0.00022f,0.00023f,0.00021f,0.00028f,0.00016f,0.00023f,0.00025f,0.00115f,0.00098f,0.00095f,0.00068f,0.00045f,0.00052f,0.00053f,0.00044f,0.00056f,0.00038f,0.00050f,0.00049f,0.00081f,0.00073f,0.00084f,0.00096f,0.00117f,0.00165f,0.00194f,0.00247f,0.00369f }
	};
	private static readonly float[][] Bands = { new[] { 450f, 1500f }, new[] { 1500f, 5000f }, new[] { 5000f, 16000f } };

	// 2nd order band-pass as a high-pass + low-pass pair (Butterworth-ish, Q 0.707 each)
	private static void Biquad(float fc, bool high, out double b0, out double b1, out double b2, out double a1, out double a2)
	{
		double w = 2.0 * Math.PI * fc / RATE, c = Math.Cos(w), s = Math.Sin(w), al = s / (2.0 * 0.7071), a0 = 1.0 + al;
		if (high) { b0 = (1 + c) / 2 / a0; b1 = -(1 + c) / a0; b2 = b0; }
		else { b0 = (1 - c) / 2 / a0; b1 = (1 - c) / a0; b2 = b0; }
		a1 = -2.0 * c / a0; a2 = (1.0 - al) / a0;
	}

	private static void Filter(float[] x, float fc, bool high)
	{
		Biquad(fc, high, out double b0, out double b1, out double b2, out double a1, out double a2);
		double x1 = 0, x2 = 0, y1 = 0, y2 = 0;
		for (int i = 0; i < x.Length; i++)
		{
			double v = x[i], y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
			x2 = x1; x1 = v; y2 = y1; y1 = y; x[i] = (float)y;
		}
	}

	private static float[] BodyBuf(int n, Random rng, float vary, double pitch, double decayK, double gain, int offset)
	{
		var y = new float[n];
		double R() => rng.NextDouble() * 2.0 - 1.0;
		for (int a = 0; a + 3 < Atoms.Length; a += 4)
		{
			double f = Atoms[a] * pitch * (1.0 + 0.03 * vary * 3.0 * R());
			double dc = Atoms[a + 1] * decayK * (1.0 + 0.25 * vary * R());
			double g = gain * (1.0 + 0.35 * vary * R());
			double ca = Atoms[a + 2] * g, sa = Atoms[a + 3] * g;
			double w = 2.0 * Math.PI * f / RATE, decay = Math.Exp(-dc / RATE);
			double c = 1.0, s = 0.0, e = 1.0, cw = Math.Cos(w), sw = Math.Sin(w);
			for (int i = offset; i < n; i++)
			{
				y[i] += (float)(e * (ca * c + sa * s));
				double c2 = c * cw - s * sw; s = s * cw + c * sw; c = c2; e *= decay;
				if ((i & 1023) == 1023) { double m = Math.Sqrt(c * c + s * s); c /= m; s /= m; }
			}
		}
		return y;
	}

	/// noise through the three rattle bands with the recording's envelope (time stretched by `stretch`, scaled by `gain`)
	private static void Rattle(float[] y, Random rng, float vary, double gain, double stretch, double hiTilt)
	{
		int n = y.Length;
		var nz = new float[n];
		for (int b = 0; b < Bands.Length; b++)
		{
			double sum = 0;
			for (int i = 0; i < n; i++) nz[i] = (float)(rng.NextDouble() * 2.0 - 1.0);
			Filter(nz, Bands[b][0], true); Filter(nz, Bands[b][0], true);
			Filter(nz, Bands[b][1], false); Filter(nz, Bands[b][1], false);
			for (int i = 0; i < n; i++) sum += nz[i] * nz[i];
			double norm = 1.0 / Math.Sqrt(sum / n + 1e-12), lvl = gain * (1.0 + 0.2 * vary * (rng.NextDouble() * 2.0 - 1.0)) * Math.Pow(hiTilt, b);
			float[] env = Env[b];
			for (int i = 0; i < n; i++)
			{
				double p = (i / stretch + 0.5) / STEP - 0.5; int k = (int)Math.Floor(p); double fr = p - k;
				if (k >= env.Length) break;
				double e0 = env[Math.Clamp(k, 0, env.Length - 1)], e1 = env[Math.Clamp(k + 1, 0, env.Length - 1)];
				y[i] += (float)(nz[i] * norm * lvl * (e0 + (e1 - e0) * fr));
			}
		}
	}

	private static readonly bool OLD_DOUBLE = DevFlags.Env("BMX_OLD_SLAMDOUBLE") is { Length: > 0 };
	private const double RATTLE_K = 1.55;   // the rattle noise louder than the recording's (user: "more rattle when we land")

	/// the bike's parts shaken by the hit (every landing, more the bigger): the chain slapping the chainstay (a low, short metallic
	/// "tchak" or two), and loose bits ticking (cable housings, the brake pads in their calipers, the chain on the cassette):
	/// short two-partial rings spread over ~20-280 ms, thinning out. Level relative to the hit already in y. t0 = shift (s).
	private static void Parts(float[] y, Random rng, double size, double t0)
	{
		int n = y.Length;
		double sz = Math.Clamp(size, 0.0, 1.0);
		double refA = Math.Max(1e-4, RmsFirst(y, 0.08));
		if (refA < 1e-3) refA = 0.08;   // (an empty buffer: the bad-landing layer)
		// chain slap: 1-2 hits, 15-60 ms after touch-down
		int slaps = 1 + (rng.NextDouble() < 0.35 + 0.5 * sz ? 1 : 0);
		for (int k = 0; k < slaps; k++)
		{
			int at = (int)((t0 + 0.015 + 0.045 * rng.NextDouble() + 0.03 * k) * RATE);
			double amp = refA * (0.55 + 0.6 * sz) * (k == 0 ? 1.0 : 0.6);
			// (metallic and light, above the hit's low end: a low partial read as a second thump)
			double[] fs = { 700.0 + 250.0 * rng.NextDouble(), 1700.0 + 500.0 * rng.NextDouble(), 3300.0 + 900.0 * rng.NextDouble() };
			double[] gs = { 0.8, 0.6, 0.35 }, ds = { 70.0, 110.0, 170.0 };
			for (int m = 0; m < 3; m++)
			{
				double w = 2.0 * Math.PI * fs[m] / RATE, ph = 6.28 * rng.NextDouble();
				for (int i = at; i < n && i < at + (int)(0.09 * RATE); i++)
				{
					double t = (i - at) / (double)RATE;
					y[i] += (float)(amp * gs[m] * Math.Exp(-ds[m] * t) * Math.Sin(w * (i - at) + ph) * Math.Min(1.0, t / 0.0008));
				}
			}
			// the rattle of the links themselves: a short burst of grit
			for (int i = at; i < n && i < at + (int)(0.025 * RATE); i++)
				y[i] += (float)(amp * 0.35 * (rng.NextDouble() * 2 - 1) * Math.Exp(-(i - at) / (0.006 * RATE)));
		}
		// loose bits ticking: many tiny rings, thinning out
		int ticks = 6 + (int)(12 * sz);
		for (int k = 0; k < ticks; k++)
		{
			double u = rng.NextDouble();
			int at = (int)((t0 + 0.02 + 0.26 * Math.Pow(u, 1.6)) * RATE);
			double fade = 1.0 - 0.75 * Math.Pow(u, 1.6);
			double amp = refA * (0.16 + 0.22 * rng.NextDouble()) * fade * (0.7 + 0.6 * sz);
			for (int m = 0; m < 2; m++)
			{
				double f = 1400.0 * Math.Pow(3.2, rng.NextDouble()), dc = 110.0 + 170.0 * rng.NextDouble(), w = 2.0 * Math.PI * f / RATE, ph = 6.28 * rng.NextDouble();
				for (int i = at; i < n && i < at + (int)(0.04 * RATE); i++)
					y[i] += (float)(amp * (m == 0 ? 1.0 : 0.6) * Math.Exp(-dc * (i - at) / RATE) * Math.Sin(w * (i - at) + ph));
			}
		}
	}

	/// the body's close resonances (51 / 66 / 68 / 76 / 81 Hz, 167 / 169 / 178 Hz) beat: the hit dies down and swells back
	/// ~50 ms later, heard as a second thump (user: "double impact, weird"). After its first peak the body may only die
	/// away: a 2 ms envelope held to its running minimum, the gain eased per sample (pitch / colour unchanged)
	private static void NoRebound(float[] y)
	{
		int n = y.Length, blk = RATE / 500;
		int nb = n / blk;
		if (nb < 4) return;
		var env = new double[nb];
		for (int b = 0; b < nb; b++)
		{
			double s = 0; for (int i = b * blk; i < (b + 1) * blk; i++) s += y[i] * y[i];
			env[b] = Math.Sqrt(s / blk) + 1e-9;
		}
		int pk = 0; for (int b = 1; b < Math.Min(nb, RATE / 20 / blk); b++) if (env[b] > env[pk]) pk = b;
		var g = new double[nb];
		double allowed = env[pk];
		for (int b = 0; b < nb; b++)
		{
			if (b <= pk) { g[b] = 1.0; continue; }
			allowed = Math.Min(allowed, env[b]);
			g[b] = Math.Min(1.0, allowed / env[b]);
		}
		for (int i = 0; i < nb * blk; i++)
		{
			double p = (i + 0.5) / blk - 0.5; int b = Math.Clamp((int)Math.Floor(p), 0, nb - 1); double fr = Math.Clamp(p - b, 0.0, 1.0);
			double gg = g[b] + (g[Math.Min(b + 1, nb - 1)] - g[b]) * fr;
			y[i] = (float)(y[i] * gg);
		}
		for (int i = nb * blk; i < n; i++) y[i] *= (float)g[nb - 1];
	}

	private static double RmsFirst(float[] y, double secs)
	{
		int m = Math.Min(y.Length, (int)(secs * RATE)); double s = 0;
		for (int i = 0; i < m; i++) s += y[i] * y[i];
		return Math.Sqrt(s / Math.Max(m, 1));
	}

	/// kind 0 = a landing slam: size 0 (a little drop) .. 0.5 (the recording) .. 1 (a big one): small = higher, quicker, lighter rattle;
	/// big = deeper, longer, more rattle + a sub thump. side 0..1 adds the tyres catching a sideways landing (the rear tyre lands a
	/// moment after the front, a scrub of rubber on dirt). kind 1 = the "bad landing" layer that follows a heavy / slammed one:
	/// the frame's second bounce, the chain and parts clattering (metallic rings), no first hit; size / side as above.
	/// seed: variant; vary: 0..0.5 how far from the recording; peak: output peak (linear)
	public float[] Render(int seed, float vary, float peak, float size = 0.5f, float side = 0f, int kind = 0)
	{
		int n = (int)(LEN * RATE);
		var rng = new Random(seed);
		double R() => rng.NextDouble() * 2.0 - 1.0;
		double sz = Math.Clamp(size, 0f, 1f) - 0.5;
		double pitch = Math.Pow(1.3, -sz * 2.0), decayK = Math.Pow(1.7, -sz * 2.0);
		double rat = 1.0 + 1.1 * sz * (sz > 0 ? 1.0 : 1.2), stretch = Math.Pow(1.3, sz * 2.0);
		float[] y;
		if (kind == 0)
		{
			y = BodyBuf(n, rng, vary, pitch, decayK, 1.0, 0);
			if (!OLD_DOUBLE) NoRebound(y);
			if (sz > 0.1)   // big: a sub thump under the body
			{
				double f0 = 52.0 * (1.0 + 0.1 * R()), dc = 14.0, w = 2.0 * Math.PI * f0 / RATE, amp = 0.55 * (sz - 0.1) / 0.4;
				for (int i = 0; i < n; i++) y[i] += (float)(amp * Math.Exp(-dc * i / RATE) * Math.Sin(w * i) * Math.Min(1.0, i / (0.004 * RATE)));
			}
			Rattle(y, rng, vary, Math.Max(0.2, rat) * (OLD_DOUBLE ? 1.0 : RATTLE_K), stretch, OLD_DOUBLE ? 1.0 : 1.12);
			if (!OLD_DOUBLE) Parts(y, rng, size, 0.0);
			if (side > 0.01)
			{
				// (the rear tyre's own second hit ~35 ms later was removed 2026-11-27: it read as a weird double impact, user;
				// OLD_DOUBLE = it back)
				if (OLD_DOUBLE)
				{
					var y2 = BodyBuf(n, rng, vary, pitch * 0.93, decayK, 0.55 * side, 0);
					Rattle(y2, rng, vary, 0.5 * side * Math.Max(0.2, rat), stretch, 1.0);
					int off = (int)((0.028 + 0.012 * (double)side) * RATE);
					for (int i = off; i < n; i++) y[i] += y2[i - off];
				}
				// rubber scrubbing sideways over dirt: band-passed noise 500-3500 Hz, swells in over ~25 ms, dies over ~0.3 s
				var sc = new float[n];
				for (int i = 0; i < n; i++) sc[i] = (float)R();
				Filter(sc, 500f, true); Filter(sc, 500f, true); Filter(sc, 3500f, false); Filter(sc, 3500f, false);
				double sum = 0; for (int i = 0; i < n; i++) sum += sc[i] * sc[i];
				double ref0 = RmsFirst(y, 0.12), gsc = 0.85 * side * ref0 / Math.Sqrt(sum / n + 1e-12);
				for (int i = 0; i < n; i++)
				{
					double t = (double)i / RATE;
					double e = Math.Min(1.0, t / 0.025) * Math.Exp(-t * (6.5 - 2.0 * side)) * (0.75 + 0.25 * Math.Sin(t * 70.0 + 3.0 * R()));
					y[i] += (float)(sc[i] * gsc * e);
				}
			}
		}
		else
		{
			// bad landing: the second bounce of the bike (a lighter, lower copy of the body 110-170 ms later) + the clatter
			// (its second bounce of the bike body, 110-170 ms later, was removed 2026-11-27: "double impact, weird"; the
			// clatter of the parts stays, and more of it)
			if (OLD_DOUBLE)
			{
				int off = (int)((0.11 + 0.06 * (R() * 0.5 + 0.5)) * RATE);
				y = BodyBuf(n, rng, vary, pitch * 0.86, decayK * 1.2, 0.5, off);
			}
			else
			{
				y = new float[n];
				Parts(y, rng, 0.6 + 0.4 * Math.Clamp(size, 0f, 1f), 0.02);
			}
			var cl = new float[n];
			Rattle(cl, rng, vary, 1.5, stretch, 1.35);
			int shift = (int)((OLD_DOUBLE ? 0.09 : 0.012) * RATE);   // (now played with the touch-down: the clatter rides the hit)
			for (int i = shift; i < n; i++) y[i] += cl[i - shift];
			// loose parts knocking: lots of tiny ticks (two short metallic partials, 1.5-4.5 kHz, 5-12 ms) between 90 and 330 ms, thinning out
			// as it settles (no late stray pings: a lone bell tone at 0.5 s read as a glitch)
			int strikes = 7 + (int)(4 * Math.Clamp(size, 0f, 1f));
			for (int k = 0; k < strikes; k++)
			{
				double u = rng.NextDouble();
				int at = (int)((0.09 + 0.24 * Math.Pow(u, 1.7)) * RATE);
				double amp = (0.10 + 0.10 * rng.NextDouble()) * (1.0 - 0.7 * (at / (double)RATE - 0.09) / 0.24);
				for (int m = 0; m < 2; m++)
				{
					double f = 1500.0 * Math.Pow(3.0, rng.NextDouble()), dc = 90.0 + 140.0 * rng.NextDouble(), w = 2.0 * Math.PI * f / RATE, ph = 6.28 * rng.NextDouble();
					for (int i = at; i < n && i < at + (int)(0.05 * RATE); i++)
						y[i] += (float)(amp * Math.Exp(-dc * (i - at) / RATE) * Math.Sin(w * (i - at) + ph));
				}
			}
		}
		// peak level + a short fade so the last samples never click
		float mx = 1e-6f;
		for (int i = 0; i < n; i++) mx = Math.Max(mx, Math.Abs(y[i]));
		float k2 = peak / mx;
		int fade = (int)(0.06 * RATE);
		for (int i = 0; i < n; i++) { float f2 = i > n - fade ? (float)(n - i) / fade : 1f; y[i] *= k2 * f2; }
		return y;
	}

	// ---------------------------------------------------------------- the bank (2026-11-24: a fresh Render on the landing step was
	// 5-10 ms of the main thread, plus a per-sample GDScript loop into a WAV). Every kind of slam is rendered ahead as 16-bit PCM on
	// .NET pool threads: kind 0 in BANK_SIZES x BANK_SIDES buckets, kind 1 in BANK_SIZES, BANK_VARIANTS each. Take() hands out the
	// nearest bucket's next ready buffer and re-renders that slot in the background with a new seed, so landings never repeat and the
	// main thread only wraps bytes into an AudioStreamWAV. Nothing here touches Godot objects off the main thread.
	public const int BANK_SIZES = 6, BANK_SIDES = 3, BANK_VARIANTS = 2;
	private byte[][] _bank;
	private int[] _next;
	private readonly object _lock = new object();
	private int _seed = 1;
	private float _vary = 0.12f, _peak = 0.63f;
	private int _busy;

	private static int Slot(int kind, int si, int di, int v) => kind == 0 ? (si * BANK_SIDES + di) * BANK_VARIANTS + v
		: BANK_SIZES * BANK_SIDES * BANK_VARIANTS + si * BANK_VARIANTS + v;
	private static float SizeOf(int si) => si / (float)(BANK_SIZES - 1);
	private static float SideOf(int di) => di / (float)(BANK_SIDES - 1);

	/// start filling the bank in the background (call once when the ride's audio is set up)
	public void StartBank(float vary, float peak)
	{
		lock (_lock)
		{
			if (_bank != null) return;
			_vary = vary; _peak = peak;
			_bank = new byte[(BANK_SIZES * BANK_SIDES + BANK_SIZES) * BANK_VARIANTS][];
			_next = new int[BANK_SIZES * BANK_SIDES + BANK_SIZES];
		}
		for (int kind = 0; kind < 2; kind++)
			for (int si = 0; si < BANK_SIZES; si++)
				for (int di = 0; di < (kind == 0 ? BANK_SIDES : 1); di++)
					for (int v = 0; v < BANK_VARIANTS; v++)
						Refill(kind, si, di, v);
	}

	/// how many renders are still running (tests / probes)
	public int BankBusy() => System.Threading.Volatile.Read(ref _busy);

	private void Refill(int kind, int si, int di, int v)
	{
		int seed;
		lock (_lock) seed = _seed++ * 7919 + 17;
		System.Threading.Interlocked.Increment(ref _busy);
		System.Threading.Tasks.Task.Run(() =>
		{
			try
			{
				var y = Render(seed, _vary, _peak, SizeOf(si), kind == 0 ? SideOf(di) : 0f, kind);
				var b = new byte[y.Length * 2];
				for (int i = 0; i < y.Length; i++)
				{
					int q = (int)(Math.Clamp(y[i], -1f, 1f) * 32767f);
					b[2 * i] = (byte)(q & 0xff); b[2 * i + 1] = (byte)((q >> 8) & 0xff);
				}
				lock (_lock) _bank[Slot(kind, si, di, v)] = b;
			}
			finally { System.Threading.Interlocked.Decrement(ref _busy); }
		});
	}

	/// a ready slam as 16-bit 48 kHz mono PCM, from the bucket nearest (size, side); empty if none is ready yet
	public byte[] Take(float size, float side, int kind)
	{
		if (_bank == null) return Array.Empty<byte>();
		int si = (int)Math.Round(Math.Clamp(size, 0f, 1f) * (BANK_SIZES - 1));
		int di = kind == 0 ? (int)Math.Round(Math.Clamp(side, 0f, 1f) * (BANK_SIDES - 1)) : 0;
		int bucket = kind == 0 ? si * BANK_SIDES + di : BANK_SIZES * BANK_SIDES + si;
		byte[] got = null; int v = 0;
		lock (_lock)
		{
			for (int k = 0; k < BANK_VARIANTS && got == null; k++)
			{
				v = (_next[bucket] + k) % BANK_VARIANTS;
				got = _bank[Slot(kind, si, di, v)];
			}
			if (got == null) return Array.Empty<byte>();
			_bank[Slot(kind, si, di, v)] = null;
			_next[bucket] = (v + 1) % BANK_VARIANTS;
		}
		Refill(kind, si, di, v);   // a new one for next time
		return got;
	}
}
