package com.mjcall.app

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.pm.PackageManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.widget.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale
import java.util.UUID

class MainActivity : Activity(), TextToSpeech.OnInitListener {
    private lateinit var column: LinearLayout
    private lateinit var organization: EditText
    private lateinit var phone: EditText
    private lateinit var purpose: EditText
    private lateinit var questions: EditText
    private lateinit var speechText: EditText
    private lateinit var notes: EditText
    private lateinit var outcome: EditText
    private lateinit var ready: CheckBox
    private lateinit var consent: CheckBox
    private lateinit var status: TextView
    private lateinit var recordButton: Button
    private lateinit var history: LinearLayout
    private lateinit var clips: LinearLayout
    private var tts: TextToSpeech? = null
    private var koreanReady = false
    private var recorder: MediaRecorder? = null
    private var player: MediaPlayer? = null
    private var pendingFile: String? = null
    private var currentId = UUID.randomUUID().toString()
    private var recordings = JSONArray()
    private var records = JSONArray()
    private var loadFailed = false
    private val store get() = File(filesDir, "records.json")

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        column = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; setPadding(24, 24, 24, 48) }
        setContentView(ScrollView(this).apply { addView(column) })
        label("mj_call · 기관·고객센터 문의")
        label("별도 전화기에서 발신하고 스피커폰을 켜 주세요. AI 자동 응답은 아직 제공하지 않습니다.")
        organization = field("전화할 곳"); phone = field("전화번호")
        purpose = field("문의 목적"); questions = field("질문 · 한 줄에 하나", 3)
        button("문의 준비 저장") { save() }
        ready = CheckBox(this).apply { text = "별도 전화기의 스피커폰을 켰어요" }; column.addView(ready)
        speechText = field("대신 말할 내용", 3)
        button("입력한 글 말하기") { if (ready.isChecked) speak(speechText.text.toString()) else message("전화기 준비를 확인해 주세요.") }
        button("준비한 질문 말하기") { if (ready.isChecked) speak(questions.text.toString()) }
        button("잠시 기다려 달라고 말하기") { if (ready.isChecked) speak("잠시만 기다려 주세요. 답변을 준비하고 있습니다.") }
        button("즉시 말하기 중지") { tts?.stop() }
        label("녹음은 이 기기의 마이크 소리입니다. 전화 회선 원본이 아니며 소음이 섞일 수 있습니다.")
        button("녹음 허락 요청 말하기") { if (ready.isChecked) speak("통화 내용을 확인하기 위해 녹음해도 괜찮을까요?") }
        consent = CheckBox(this).apply { text = "상대에게 녹음을 안내하고 허락을 확인했어요" }; column.addView(consent)
        status = TextView(this); column.addView(status)
        recordButton = button("녹음 시작") { if (recorder != null) stopRecording(false) else startRecording() }
        outcome = field("문의 결과 (미확인·일부 답변·회신 대기 등)")
        notes = field("답변·서류·기한·접수번호 메모", 4)
        button("결과·메모 저장") { save() }
        label("실제 전화는 전화기에서 종료해 주세요.")
        clips = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }; column.addView(clips)
        button("듣기 중지") { player?.release(); player = null }
        button("새 문의") { if (recorder == null) { clear(); showHistory() } }
        button("현재 문의와 녹음 삭제") { confirmDelete() }
        label("저장한 문의·통화 기록")
        history = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }; column.addView(history)
        try { if (store.exists()) records = JSONArray(store.readText()) } catch (_: Exception) { loadFailed = true; message("기록을 읽지 못했습니다. 기존 파일은 덮어쓰지 않습니다.") }
        showHistory(); tts = TextToSpeech(this, this)
    }
    override fun onInit(code: Int) {
        koreanReady = code == TextToSpeech.SUCCESS && (tts?.setLanguage(Locale.KOREAN) ?: -1) >= 0
        if (!koreanReady) message("기기 TTS 설정에서 한국어 음성을 설치해 주세요.")
        tts?.setSpeechRate(0.85f)
    }
    private fun speak(text: String) {
        if (!koreanReady) { message("한국어 음성이 준비되지 않았어요."); return }
        if (text.isNotBlank()) tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, UUID.randomUUID().toString())
    }
    private fun label(text: String) { column.addView(TextView(this).apply { this.text = text; textSize = 18f; setPadding(0, 12, 0, 12) }) }
    private fun field(hint: String, lines: Int = 1): EditText = EditText(this).apply { this.hint = hint; minLines = lines; maxLines = lines + 3; column.addView(this) }
    private fun button(text: String, action: () -> Unit): Button = Button(this).apply { this.text = text; minHeight = 56; setOnClickListener { action() }; column.addView(this) }
    private fun message(text: String) { status.text = text }
    private fun current(): JSONObject = JSONObject().put("id", currentId).put("organization", organization.text.toString()).put("phone", phone.text.toString()).put("purpose", purpose.text.toString()).put("questions", questions.text.toString()).put("notes", notes.text.toString()).put("outcome", outcome.text.toString()).put("recordings", recordings)
    private fun save(): Boolean {
        if (loadFailed) { message("기존 기록 읽기 오류가 있어 저장하지 않습니다."); return false }
        if (organization.text.isBlank() || purpose.text.isBlank()) { message("전화할 곳과 목적을 입력해 주세요."); return false }
        val next = JSONArray().put(current())
        for (i in 0 until records.length()) if (records.getJSONObject(i).getString("id") != currentId) next.put(records.getJSONObject(i))
        return try {
            val temporary = File(filesDir, "records.tmp"); temporary.writeText(next.toString(2))
            java.nio.file.Files.move(temporary.toPath(), store.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE)
            records = next; showHistory(); message("저장했어요."); true
        } catch (_: Exception) { message("저장에 실패했어요. 화면을 유지하고 다시 저장해 주세요."); false }
    }
    @Suppress("DEPRECATION")
    private fun startRecording() {
        if (!ready.isChecked || !consent.isChecked) { message("전화기 준비와 녹음 허락을 확인해 주세요."); return }
        if (!save()) return
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 1); message("권한 허용 후 녹음 시작을 다시 눌러 주세요."); return
        }
        var next: MediaRecorder? = null
        try {
            player?.release(); player = null
            val name = "call_${UUID.randomUUID()}.m4a"
            next = MediaRecorder().apply { setAudioSource(MediaRecorder.AudioSource.MIC); setOutputFormat(MediaRecorder.OutputFormat.MPEG_4); setAudioEncoder(MediaRecorder.AudioEncoder.AAC); setOutputFile(File(filesDir, name).path); prepare(); start() }
            recorder = next; pendingFile = name; recordButton.text = "녹음 중지·저장"; consent.isEnabled = false; message("● 녹음 중 — 화면을 열어 두세요")
        } catch (_: Exception) { next?.release(); message("녹음을 시작하지 못했어요.") }
    }
    private fun stopRecording(interrupted: Boolean) {
        val active = recorder ?: return; recorder = null
        try {
            active.stop()
            pendingFile?.let { recordings.put(JSONObject().put("file", it).put("interrupted", interrupted)); save() }
        } catch (_: Exception) { message("녹음 종료에 실패했어요. 마지막 구간이 누락되었을 수 있어요.") }
        finally { active.release(); pendingFile = null; consent.isEnabled = true; recordButton.text = "녹음 시작"; showClips() }
    }
    private fun clear() { currentId = UUID.randomUUID().toString(); for (field in listOf(organization, phone, purpose, questions, notes, outcome, speechText)) field.setText(""); recordings = JSONArray(); ready.isChecked = false; consent.isChecked = false; showClips() }
    private fun showHistory() {
        history.removeAllViews()
        for (i in 0 until records.length()) {
            val item = records.getJSONObject(i)
            history.addView(Button(this).apply { text = "${item.optString("organization")} · ${item.optString("purpose")}"; setOnClickListener {
                if (recorder != null) return@setOnClickListener
                currentId = item.getString("id"); organization.setText(item.optString("organization")); phone.setText(item.optString("phone")); purpose.setText(item.optString("purpose")); questions.setText(item.optString("questions")); notes.setText(item.optString("notes")); outcome.setText(item.optString("outcome")); recordings = item.optJSONArray("recordings") ?: JSONArray(); ready.isChecked = false; consent.isChecked = false; showClips()
            } })
        }
    }
    private fun showClips() {
        clips.removeAllViews()
        for (i in 0 until recordings.length()) {
            val clip = recordings.getJSONObject(i); val name = clip.getString("file")
            clips.addView(Button(this).apply { text = "녹음 ${i + 1} 듣기${if (clip.optBoolean("interrupted")) " · 중단됨" else ""}"; setOnClickListener {
                if (recorder != null || File(name).name != name || !name.startsWith("call_")) return@setOnClickListener
                try { player?.release(); player = MediaPlayer().apply { setDataSource(File(filesDir, name).path); prepare(); start() } } catch (_: Exception) { message("재생하지 못했어요.") }
            } })
        }
    }
    private fun confirmDelete() {
        if (recorder != null) return
        AlertDialog.Builder(this).setMessage("현재 문의와 연결된 녹음을 삭제할까요?").setNegativeButton("취소", null).setPositiveButton("삭제") { _, _ ->
            try {
                player?.release(); player = null
                for (i in 0 until recordings.length()) { val name = recordings.getJSONObject(i).getString("file"); require(File(name).name == name && name.startsWith("call_")); val file = File(filesDir, name); if (file.exists() && !file.delete()) error("delete failed") }
                val next = JSONArray(); for (i in 0 until records.length()) if (records.getJSONObject(i).getString("id") != currentId) next.put(records.getJSONObject(i))
                File(filesDir, "records.tmp").also { it.writeText(next.toString()); java.nio.file.Files.move(it.toPath(), store.toPath(), java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE) }
                records = next; clear(); showHistory()
            } catch (_: Exception) { message("삭제하지 못했어요. 다시 시도해 주세요.") }
        }.show()
    }
    override fun onPause() { tts?.stop(); stopRecording(true); if (::organization.isInitialized && organization.text.isNotBlank()) save(); super.onPause() }
    override fun onDestroy() { tts?.shutdown(); player?.release(); recorder?.release(); super.onDestroy() }
}
