import Foundation

extension MusicVideoStudio {
    /// Everything a frame needs besides the clock: the project, the analysed spectra and where
    /// media files live. The preview and the exporter both draw from this, so they cannot disagree.
    struct FrameResources {
        var project: VideoProject
        var spectra: [String: SpectrumData]
        var mediaURL: (String) -> URL

        func photoURL(_ layer: PhotoLayer) -> URL { mediaURL(layer.mediaFile) }

        private func audioFile(_ id: UUID?) -> String? {
            id.flatMap { id in project.audios.first { $0.core.id == id }?.mediaFile }
        }

        func spectrum(for layer: VisualizerLayer) -> SpectrumData? {
            audioFile(layer.audioLayerID).flatMap { spectra[$0] }
        }

        /// Beats (project seconds) that drive a beat effect: the linked clip's beats, every n-th.
        func effectBeats(for layer: EffectLayer) -> [Double] {
            guard layer.kind.needsAudio, let id = layer.audioLayerID,
                  let audio = project.audios.first(where: { $0.core.id == id }),
                  let data = spectra[audio.mediaFile] else { return [] }
            return EffectMath.projectBeats(fileBeats: data.beats, offset: audio.core.start.seconds - audio.sourceStart,
                                           from: audio.core.start.seconds, to: audio.core.end.seconds, every: layer.everyBeats)
        }

        /// Shake / Beat Pulse motion for the pictures at `time`.
        func sceneMotion(items: [RenderItem], at time: ProjectTime) -> SceneMotion {
            let effects = items.compactMap { item -> EffectLayer? in
                if case .effect(let layer) = item { return layer }
                return nil
            }
            guard !effects.isEmpty else { return .identity }
            return EffectMath.sceneMotion(effects: effects, at: time, beats: { effectBeats(for: $0) })
        }
    }
}
