tool
extends EditorPlugin

const SELEX_SCANCODE = KEY_D
const UNDO_SCANCODE = 90
const REDO_SCANCODE = 90
const PASTE_SCANCODE = 86
const COPY_SCANCODE = 67
const CUT_SCANCODE = 88

var script_editor: ScriptEditor
var editor_settings: EditorSettings

var selected_words: Array = []
var last_selected_word: String = ""
var last_selected_word_length: int = 0

var text_length: int = 0

var selected_search: bool = false
var selected_undo_redo: bool = false

var edit_num: int = 0
var undo_num: int = 0

func _enter_tree() -> void:
	prints("Selector plugin:", "enter")
	self.script_editor = self.get_editor_interface().get_script_editor()
	self.editor_settings = self.get_editor_interface().get_editor_settings()

	var input_event = InputEventKey.new()
	input_event.scancode = SELEX_SCANCODE
	input_event.command = true

	ShortCut.new().set_shortcut(input_event)

func _exit_tree() -> void:
	prints("Selector plugin:", "exit")

func _input(event) -> void:
	self.selected_search = false
	self.selected_undo_redo = false

	if event is InputEventKey && event.pressed:
		if SELEX_SCANCODE == event.scancode && event.command:
			self.search()
			self.selected_search = true
		elif (
			event.scancode in [CUT_SCANCODE, COPY_SCANCODE, PASTE_SCANCODE]
			&& event.command
		):
			pass
		elif KEY_BACKSPACE == event.scancode:
			self.block_backspace()
		elif (
			self.undo_num > 0
			&& event.scancode == UNDO_SCANCODE
			&& (event.command || event.control)
			&& event.shift
		):
			self.redo_selected_words()
			self.selected_undo_redo = true
		elif (
			self.edit_num > 0
			&& event.scancode == UNDO_SCANCODE
			&& (event.command || event.control)
			&& not event.shift
		):
			self.undo_selected_words()
			self.selected_undo_redo = true
		elif (
			self.edit_num == 0
			&& event.scancode == UNDO_SCANCODE
			&& (event.command || event.control)
			&& not event.shift
		):
			self.reset_selected_words()
		elif (
			(event.scancode && event.command)
			|| (event.scancode && event.command && event.shift)
		):
			self.selected_undo_redo = true
		elif (
			event.scancode && event.alt || event.scancode && event.control
		):
			self.reset_selected_words()

	if event is InputEventMouseButton && event.pressed:
		self.reset_selected_words()

func _search_text_edit(node) -> TextEdit:
	for child in node.get_children():
		if child is TextEdit:
			if not child.is_connected("text_changed", self, "_edit_selected_words"):
				child.connect("text_changed", self, "_edit_selected_words")
			if not child.is_connected("cursor_changed", self, "_update_last_selected_word"):
				child.connect("cursor_changed", self, "_update_last_selected_word")
			return child
		return self._search_text_edit(child)
	return null

func get_editor() -> TextEdit:
	var current_script = self.script_editor.get_current_script()
	var open_scripts = self.script_editor.get_open_scripts()

	var tabs = self.script_editor.get_child(0).get_child(1).get_child(1)
	for i in range(len(open_scripts)):
		if open_scripts[i] == current_script:
			var ste = tabs.get_child(i)
			if ste.get_class() == "ScriptTextEditor":
				return self._search_text_edit(ste)
	return null

func search() -> void:
	self.editor_settings.set_setting("text_editor/completion/auto_brace_complete", false)

	var editor = self.get_editor()
	if editor && editor is TextEdit && editor.is_selection_active():
		self.text_length = len(editor.text)

		var selected_text = editor.get_selection_text()
		self._search_words(editor, selected_text)

func _search_words(editor: TextEdit, selected_text: String) -> void:
	var line = editor.cursor_get_line()
	var col = editor.cursor_get_column()

	if self.last_selected_word != selected_text:
		self.selected_words = []
		self.last_selected_word = selected_text
		self.last_selected_word_length = len(self.last_selected_word)
		self.selected_words.append([col - self.last_selected_word_length, line])

	var next_word = editor.search(
		selected_text, TextEdit.SEARCH_MATCH_CASE, line, col
	)

	if next_word.size()>0:
		var has_word = false
		for word in self.selected_words:
			if word[0] == next_word[0] and word[1] == next_word[1]:
				has_word = true

		if not has_word:
			self.selected_words.append(next_word)

			var last_col = next_word[TextEdit.SEARCH_RESULT_COLUMN]
			var last_line = next_word[TextEdit.SEARCH_RESULT_LINE]

			editor.cursor_set_line(last_line)
			editor.cursor_set_column(last_col + self.last_selected_word_length)
			editor.select(
				last_line, last_col,
				last_line, last_col + self.last_selected_word_length
			)

func _unblock_backspace(editor: TextEdit) -> void:
	if editor && editor is TextEdit:
		if editor.is_readonly():
			editor.set_readonly(false)

func block_backspace() -> void:
	if not self.selected_words:
		return

	var editor = self.get_editor()
	if editor && editor is TextEdit:
		if not self.last_selected_word:
			editor.set_readonly(true)
			self.call_deferred("_unblock_backspace", editor)

func _update_last_selected_word_length(editor: TextEdit, number_changes: int) -> int:
	var chars_diff = (self.text_length - len(editor.text)) / number_changes
	self.last_selected_word_length -= chars_diff
	return chars_diff

func _restore_selected_words(editor: TextEdit, is_undo: bool) -> void:
	for i in range((len(self.selected_words) - 1) * 2):
		if is_undo:
			if editor.has_undo():
				editor.undo()
		else:
			if editor.has_redo():
				editor.redo()

	var chars_diff = self._update_last_selected_word_length(editor, len(self.selected_words))

	var words_in_line = 0
	var current_line = self.selected_words[0][TextEdit.SEARCH_RESULT_LINE]
	for i in range(len(self.selected_words)):
		var word = self.selected_words[i]
		if word[TextEdit.SEARCH_RESULT_LINE] != current_line:
			words_in_line = 0
			current_line = word[TextEdit.SEARCH_RESULT_LINE]

		self.selected_words[i][TextEdit.SEARCH_RESULT_COLUMN] -= chars_diff * words_in_line
		words_in_line += 1

	var line = self.selected_words[-1][TextEdit.SEARCH_RESULT_LINE]
	var col = self.selected_words[-1][TextEdit.SEARCH_RESULT_COLUMN]
	var cursor_column = col + len(self.last_selected_word) - chars_diff

	editor.cursor_set_line(line)
	editor.cursor_set_column(cursor_column)
	editor.select(line, col, line, cursor_column)
#
	self.last_selected_word = editor.get_selection_text()
	self.text_length = len(editor.text)
	editor.deselect()

func undo_selected_words():
	if not self.selected_words:
		return

	var editor = self.get_editor()
	if editor && editor is TextEdit:
		self.edit_num -= 1
		self.undo_num += 1
		self.call_deferred("_restore_selected_words", editor, true)

func redo_selected_words():
	if not self.selected_words:
		return

	var editor = self.get_editor()
	if editor && editor is TextEdit:
		self.edit_num += 1
		self.undo_num -= 1
		self.call_deferred("_restore_selected_words", editor, false)

func _get_last_word_bounds(editor: TextEdit, last_word: Array) -> Dictionary:
	return {
		line = last_word[TextEdit.SEARCH_RESULT_LINE],
		column = last_word[TextEdit.SEARCH_RESULT_COLUMN],
		cursor_line = editor.cursor_get_line(),
		cursor_column = editor.cursor_get_column()
	}

func _select_last_word(editor: TextEdit, bounds: Dictionary) -> String:
	editor.select(
		bounds.line, bounds.column, bounds.line, bounds.cursor_column
	)
	var word = editor.get_selection_text()
	editor.deselect()
	return word

func _update_last_selected_word() -> void:
	if self.selected_undo_redo  || self.selected_search || not self.selected_words:
		return

	var editor = self.get_editor()
	if editor && editor is TextEdit:
		var last_bounds = self._get_last_word_bounds(editor, self.selected_words[-1])

		editor.cursor_set_line(last_bounds.line)
		if (
			last_bounds.cursor_column < last_bounds.column
			|| last_bounds.cursor_column > last_bounds.column + self.last_selected_word_length
		):
			if last_bounds.cursor_column < last_bounds.column:
				editor.cursor_set_column(last_bounds.column + self.last_selected_word_length)
			elif last_bounds.cursor_column > last_bounds.column + self.last_selected_word_length:
				editor.cursor_set_column(last_bounds.column)
			return

		self.last_selected_word = self._select_last_word(editor, last_bounds)

func _edit_selected_words() -> void:
	if self.selected_undo_redo || self.selected_search || not self.selected_words:
		return

	var editor = self.get_editor()
	if editor && editor is TextEdit:
		var last_word = self.selected_words.pop_back()
		var last_bounds = self._get_last_word_bounds(editor, last_word)

		# reset if paste couple lines
		if last_bounds.cursor_line != last_bounds.line:
			self.reset_selected_words()
			return

		editor.cursor_set_line(last_bounds.line)
		editor.cursor_set_column(last_bounds.cursor_column)

		var selected_text = self._select_last_word(editor, last_bounds)

		var count_updated = {last_bounds.line: 0}
		var chars_diff: int = self._update_last_selected_word_length(editor, 1)
		var len_before_edit = len(editor.text)
		for i in range(len(self.selected_words)):
			var word = self.selected_words[i]
			var word_col = word[TextEdit.SEARCH_RESULT_COLUMN]
			var word_line = word[TextEdit.SEARCH_RESULT_LINE]

			if not count_updated.has(word_line):
				count_updated[word_line] = 0

			var count_chars: int = count_updated[word_line]
			self.selected_words[i][TextEdit.SEARCH_RESULT_COLUMN] -= count_chars

			editor.select(
				word_line, word_col - count_chars,
				word_line, word_col + len(self.last_selected_word) - count_chars
			)

			editor.cursor_set_line(word_line)
			if len(self.last_selected_word) == 0:
				editor.cursor_set_column(word_col - count_chars)
			else:
				editor.cursor_set_column(word_col)

			editor.insert_text_at_cursor(selected_text)

			# update column
			if selected_text:
				count_updated[word_line] += chars_diff
			else:
				count_updated[word_line] += len(self.last_selected_word)

		editor.cursor_set_line(last_bounds.line)
		editor.cursor_set_column(
			last_bounds.cursor_column - count_updated[last_bounds.line]
		)

		# restore last word
		self.selected_words.append(
			[
				last_bounds.column - count_updated[last_bounds.line],
				last_bounds.line
			]
		)

		self.last_selected_word = selected_text
		self.text_length = len(editor.text)
		editor.deselect()

		self.edit_num += 1

func reset_selected_words() -> void:
	self.editor_settings.set_setting("text_editor/completion/auto_brace_complete", true)

	self.selected_words = []
	self.last_selected_word = ""
	self.last_selected_word_length = 0

	self.edit_num = 0
	self.undo_num = 0
