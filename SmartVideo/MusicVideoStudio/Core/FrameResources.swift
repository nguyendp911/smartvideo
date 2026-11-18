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

        /// Spectrum frame for a record's swell / equalizer ring (nil when it does not use the music).
        func vinylAudio(_ layer: VinylLayer, at time: ProjectTime) -> VisualizerFrame? {
            guard layer.beatPulse > 0 || layer.equalizerRing, let id = layer.audioLayerID,
                  let audio = project.audios.first(where: { $0.core.id == id }),
                  let data = spectra[audio.mediaFile] else { return nil }
            let source = time.seconds - (audio.core.start.seconds - audio.sourceStart)
            return VisualizerFrame(bands: data.bands(at: source, count: 48, decay: 0.7), bass: data.bass(at: source),
                                   pulse: data.beatPulse(at: source))
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
