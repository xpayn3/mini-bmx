using UnityEditor;
using UnityEngine;

namespace Runout.EditorTools
{
    /// Every model under Art/Characters imports as a Unity Humanoid (Mecanim avatar made from the model, the standard
    /// bone map), in metres, with its materials taken from the file. So any Humanoid character (Mixamo, Unity's, a scan)
    /// dropped there is a rider: RiderView retargets our pose onto its bones.
    public sealed class CharacterImport : AssetPostprocessor
    {
        const string DIR = "Assets/Runout/Art/Characters/";

        void OnPreprocessModel()
        {
            if (!assetPath.StartsWith(DIR)) return;
            var mi = (ModelImporter)assetImporter;
            mi.animationType = ModelImporterAnimationType.Human;
            mi.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            mi.useFileScale = true;
            mi.importAnimation = false;   // (the pose is ours; clips come in through their own files)
            mi.materialImportMode = ModelImporterMaterialImportMode.ImportViaMaterialDescription;
        }
    }
}
