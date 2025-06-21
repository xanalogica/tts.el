;;; tts.el --- Text-to-Speech integration with ElevenLabs or local engines -*- lexical-binding: t; -*-

;; Author: Your Name <your.email@example.com>
;; Version: 0.1
;; Package-Requires: ((emacs "27.1"))
;; Keywords: multimedia, speech, accessibility
;; URL: https://github.com/YOUR-GITHUB-USER/tts.el

;;; Commentary:

;; A simple Emacs interface for text-to-speech using either ElevenLabs or a local engine.
;; Select a region or point-to-end, press a key, and hear it read aloud.
;; Playback supports pause/resume/toggle and shows visual feedback in the mode-line.

;;; Code:

(defgroup tts nil
  "Text-to-speech integration for Emacs."
  :group 'multimedia)

(defcustom tts-backend 'elevenlabs
  "TTS backend to use: 'elevenlabs or 'local."
  :type '(choice (const :tag "ElevenLabs API" elevenlabs)
                 (const :tag "Local TTS Engine" local)))

(defcustom tts-elevenlabs-api-key nil
  "API key for ElevenLabs."
  :type 'string)

(defcustom tts-elevenlabs-default-voice-id "EXAVITQu4vr4xnSDxMaL"
  "Default voice ID for ElevenLabs API."
  :type 'string)

(defcustom tts-elevenlabs-voices nil
  "Alist of named ElevenLabs voices: ((\"Rachel\" . \"EXA...\") ...)."
  :type '(alist :key-type string :value-type string))

(defcustom tts-local-command "espeak"
  "Local TTS command. Can be 'espeak', or a shell script for piper etc."
  :type 'string)

(defvar tts--queue nil "Internal speech job queue.")
(defvar tts--current-process nil "Currently active playback process.")
(defvar tts--paused nil "Whether the current playback is paused.")
(defvar tts--mode-line-string nil "Mode line string for TTS status display.")

(put 'tts--mode-line-string 'risky-local-variable t)

(defun tts--cleanup ()
  "Stop and cleanup any current playback."
  (when (process-live-p tts--current-process)
    (kill-process tts--current-process))
  (setq tts--queue nil
        tts--current-process nil
        tts--paused nil)
  (tts--update-mode-line nil))

(defun tts--update-mode-line (status)
  "Update mode-line to show TTS STATUS."
  (setq tts--mode-line-string
        (pcase status
          ('playing " 🔊")
          ('paused  " ⏸")
          (_        nil)))
  (force-mode-line-update t))

(defun tts--play-next ()
  "Play the next audio job in the queue."
  (when-let ((job (pop tts--queue)))
    (pcase job
      (`(:file ,file)
       (setq tts--current-process
             (start-process "tts-play" nil "mpv" "--no-terminal" file))
       (tts--update-mode-line 'playing)
       (set-process-sentinel
        tts--current-process
        (lambda (_e _m)
          (delete-file file)
          (setq tts--current-process nil)
          (tts--update-mode-line nil)
          (tts--play-next))))
      (`(:local ,text)
       (setq tts--current-process
             (start-process "tts-local" nil tts-local-command text))
       (tts--update-mode-line 'playing)
       (set-process-sentinel
        tts--current-process
        (lambda (_e _m)
          (setq tts--current-process nil)
          (tts--update-mode-line nil)
          (tts--play-next))))))

(defun tts--queue-job (job)
  "Add JOB to playback queue and trigger if idle."
  (push job tts--queue)
  (unless tts--current-process
    (tts--play-next)))

(defun tts--select-voice ()
  "Prompt for voice from `tts-elevenlabs-voices`."
  (let* ((choices (mapcar #'car tts-elevenlabs-voices))
         (name (completing-read "Choose voice: " choices nil t))
         (id (cdr (assoc name tts-elevenlabs-voices))))
    (or id tts-elevenlabs-default-voice-id)))

(defun tts--speak-elevenlabs (text &optional voice-id)
  "Send TEXT to ElevenLabs API and queue playback."
  (let ((clean-text (replace-regexp-in-string "\"" "\\\"" text))
        (voice (or voice-id tts-elevenlabs-default-voice-id))
        (tmpfile (make-temp-file "tts" nil ".mp3")))
    (call-process "curl" nil nil nil
                  "-s"
                  "-X" "POST"
                  (format "https://api.elevenlabs.io/v1/text-to-speech/%s/stream" voice)
                  "-H" (format "xi-api-key: %s" tts-elevenlabs-api-key)
                  "-H" "Content-Type: application/json"
                  "-d" (format "{\"text\":\"%s\"}" clean-text)
                  "--output" tmpfile)
    (tts--queue-job `(:file ,tmpfile))))

(defun tts--speak-local (text)
  "Send TEXT to local TTS engine."
  (tts--queue-job `(:local ,text)))

;;;###autoload
(defun tts-speak (&optional choose-voice)
  "Speak region or text from point to end. Cancels existing playback.
With prefix arg, select voice interactively."
  (interactive "P")
  (tts--cleanup)
  (let* ((text (if (use-region-p)
                   (buffer-substring-no-properties (region-beginning) (region-end))
                 (buffer-substring-no-properties (point) (point-max))))
         (voice (when choose-voice (tts--select-voice))))
    (pcase tts-backend
      ('elevenlabs (tts--speak-elevenlabs text voice))
      ('local (tts--speak-local text)))))

;;;###autoload
(defun tts-pause ()
  "Pause current TTS playback, if supported."
  (interactive)
  (when (and (process-live-p tts--current-process)
             (not tts--paused))
    (signal-process tts--current-process 'SIGSTOP)
    (setq tts--paused t)
    (tts--update-mode-line 'paused)
    (message "TTS paused.")))

;;;###autoload
(defun tts-resume ()
  "Resume paused TTS playback, if supported."
  (interactive)
  (when (and (process-live-p tts--current-process)
             tts--paused)
    (signal-process tts--current-process 'SIGCONT)
    (setq tts--paused nil)
    (tts--update-mode-line 'playing)
    (message "TTS resumed.")))

;;;###autoload
(defun tts-toggle-play ()
  "Toggle between pause and resume."
  (interactive)
  (if tts--paused
      (tts-resume)
    (tts-pause)))

;;;###autoload
(define-minor-mode tts-mode
  "Minor mode for displaying TTS status in the mode-line."
  :global t
  :lighter nil
  (if tts-mode
      (unless (memq 'tts--mode-line-string global-mode-string)
        (setq global-mode-string
              (append global-mode-string '(tts--mode-line-string))))
    (setq global-mode-string
          (remove 'tts--mode-line-string global-mode-string))))

(provide 'tts)
;;; tts.el ends here
