tool
extends EditorPlugin

# Expand selection with Cmd+D & edit text in selected regions

const SELEX_SCANCODE = KEY_D
const UNDO_SCANCODE = 90
const REDO_SCANCODE = 90
const PASTE_SCANCODE = 86
const COPY_SCANCODE = 67
const CUT_SCANCODE = 88

var script_editor: ScriptEditor
var editor_settings: EditorSettings

var os_name = OS.get_name()
var selex_shortcut: ShortCut = null

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
	script_editor = get_editor_interface().get_script_editor()
	editor_settings = get_editor_interface().get_editor_settings()

	var input_event = InputEventKey.new()
	input_event.scancode = SELEX_SCANCODE
	if os_name == 'OSX':
		input_event.command = true
	else:
		input_event.control = true

	selex_shortcut = ShortCut.new()
	selex_shortcut.set_shortcut(input_event)

func _exit_tree() -> void:
	prints("Selector plugin:", "exit")

func _input(event) -> void:
	selected_search = false
	selected_undo_redo = false

	if event is InputEventKey && event.pressed:
		var cmd_key = event.command if os_name == 'OSX' else event.control

		if selex_shortcut.is_shortcut(event):
			search()
			selected_search = true
		elif (
			event.scancode in [CUT_SCANCODE, COPY_SCANCODE, PASTE_SCANCODE]
			&& cmd_key
		):
			pass
		elif KEY_BACKSPACE == event.scancode:
			block_backspace()
		elif (
			undo_num > 0
			&& event.scancode == UNDO_SCANCODE
			&& cmd_key
			&& event.shift
		):
			redo_selected_words()
			selected_undo_redo = true
		elif (
			undo_num > 0
			&& event.scancode == KEY_Y
			&& cmd_key
		):
			redo_selected_words()
			selected_undo_redo = true
		elif (
			edit_num > 0
			&& event.scancode == UNDO_SCANCODE
			&& cmd_key
			&& not event.shift
		):
			undo_selected_words()
			selected_undo_redo = true
		elif (
			edit_num == 0
			&& event.scancode == UNDO_SCANCODE
			&& cmd_key
			&& not event.shift
		):
			reset_selected_words()
		elif (
			(event.scancode && cmd_key)
			|| (event.scancode && cmd_key && event.shift)
		):
			selected_undo_redo = true
		elif (
			event.scancode && event.alt
			|| event.scancode && event.control
			|| event.scancode && event.command
		):
			reset_selected_words()

	if event is InputEventMouseButton && event.pressed:
		reset_selected_words()


# search
func search_text_edit(node) -> TextEdit:
	for child in node.get_children():
		if child is TextEdit:
			if not child.is_connected(
			   "text_changed",
			   self,
			   "_on_TextEdit_edit_selected_words"
			):
				child.connect(
					"text_changed",
					self,
					"_on_TextEdit_edit_selected_words"
				)
			if not child.is_connected(
			   "cursor_changed",
			   self,
			   "_on_TextEdit_update_last_selected_word"
			):
				child.connect(
					"cursor_changed",
					self,
					"_on_TextEdit_update_last_selected_word"
				)
			return child
		return search_text_edit(child)
	return null

func get_editor() -> TextEdit:
	var current_script = script_editor.get_current_script()
	var open_scripts = script_editor.get_open_scripts()

	var tabs = script_editor.get_child(0).get_child(1).get_child(1)
	for i in range(open_scripts.size()):
		if open_scripts[i] == current_script:
			var ste = tabs.get_child(i)
			if ste.get_class() == "ScriptTextEditor":
				return search_text_edit(ste)
	return null

func search_words(editor: TextEdit, selected_text: String) -> void:
	var line = editor.cursor_get_line()
	var col = editor.cursor_get_column()

	if last_selected_word != selected_text:
		selected_words = []
		last_selected_word = selected_text
		last_selected_word_length = len(last_selected_word)
		selected_words.append([col - last_selected_word_length, line])

	var next_word = editor.search(
		selected_text, TextEdit.SEARCH_MATCH_CASE, line, col
	)

	if next_word.size()>0:
		var has_word = false
		for word in selected_words:
			if word[0] == next_word[0] and word[1] == next_word[1]:
				has_word = true

		if not has_word:
			selected_words.append(next_word)

			var last_col = next_word[TextEdit.SEARCH_RESULT_COLUMN]
			var last_line = next_word[TextEdit.SEARCH_RESULT_LINE]

			editor.cursor_set_line(last_line)
			editor.cursor_set_column(last_col + last_selected_word_length)
			editor.select(
				last_line, last_col,
				last_line, last_col + last_selected_word_length
			)

func search() -> void:
	editor_settings.set_setting("text_editor/completion/auto_brace_complete", false)

	var editor = get_editor()
	if editor && editor is TextEdit && editor.is_selection_active():
		text_length = len(editor.text)

		var selected_text = editor.get_selection_text()
		search_words(editor, selected_text)


# block backspace
func unblock_backspace(editor: TextEdit) -> void:
	if editor && editor is TextEdit:
		if editor.is_readonly():
			editor.set_readonly(false)

func block_backspace() -> void:
	if not selected_words:
		return

	var editor = get_editor()
	if editor && editor is TextEdit:
		if not last_selected_word:
			editor.set_readonly(true)
			call_deferred("unblock_backspace", editor)


# undo/redo
func update_last_selected_word_length(editor: TextEdit, number_changes: int) -> int:
	var chars_diff = (text_length - len(editor.text)) / number_changes
	last_selected_word_length -= chars_diff
	return chars_diff

func restore_selected_words(editor: TextEdit, is_undo: bool) -> void:
	var selected_words_size = selected_words.size()
	for i in range((selected_words_size - 1) * 2):
		if is_undo:
			if editor.has_undo():
				editor.undo()
		else:
			if editor.has_redo():
				editor.redo()

	var chars_diff = update_last_selected_word_length(editor, selected_words_size)

	var words_in_line = 0
	var current_line = selected_words[0][TextEdit.SEARCH_RESULT_LINE]
	for i in range(selected_words_size):
		var word = selected_words[i]
		if word[TextEdit.SEARCH_RESULT_LINE] != current_line:
			words_in_line = 0
			current_line = word[TextEdit.SEARCH_RESULT_LINE]

		selected_words[i][TextEdit.SEARCH_RESULT_COLUMN] -= chars_diff * words_in_line
		words_in_line += 1

	var line = selected_words[-1][TextEdit.SEARCH_RESULT_LINE]
	var col = selected_words[-1][TextEdit.SEARCH_RESULT_COLUMN]
	var cursor_column = col + len(last_selected_word) - chars_diff

	editor.cursor_set_line(line)
	editor.cursor_set_column(cursor_column)
	editor.select(line, col, line, cursor_column)
#
	last_selected_word = editor.get_selection_text()
	text_length = len(editor.text)
	editor.deselect()

func undo_selected_words() -> void:
	if not selected_words:
		return

	var editor = get_editor()
	if editor && editor is TextEdit:
		edit_num -= 1
		undo_num += 1
		call_deferred("restore_selected_words", editor, true)

func redo_selected_words() -> void:
	if not selected_words:
		return

	var editor = get_editor()
	if editor && editor is TextEdit:
		edit_num += 1
		undo_num -= 1
		call_deferred("restore_selected_words", editor, false)


# reset selected words
func reset_selected_words() -> void:
	editor_settings.set(
		"text_editor/completion/auto_brace_complete", true
	)

	selected_words = []
	last_selected_word = ""
	last_selected_word_length = 0

	edit_num = 0
	undo_num = 0


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

func _on_TextEdit_update_last_selected_word() -> void:
	if selected_undo_redo  || selected_search || not selected_words:
		return

	var editor = get_editor()
	if editor && editor is TextEdit:
		var last_bounds = _get_last_word_bounds(editor, selected_words[-1])

		editor.cursor_set_line(last_bounds.line)
		if (
			last_bounds.cursor_column < last_bounds.column
			|| last_bounds.cursor_column > last_bounds.column + last_selected_word_length
		):
			if last_bounds.cursor_column < last_bounds.column:
				editor.cursor_set_column(last_bounds.column + last_selected_word_length)
			elif last_bounds.cursor_column > last_bounds.column + last_selected_word_length:
				editor.cursor_set_column(last_bounds.column)
			return

		last_selected_word = _select_last_word(editor, last_bounds)

func _on_TextEdit_edit_selected_words() -> void:
	if selected_undo_redo || selected_search || not selected_words:
		return

	var editor = get_editor()
	if editor && editor is TextEdit:
		var last_word = selected_words.pop_back()
		var last_bounds = _get_last_word_bounds(editor, last_word)

		# reset if paste couple lines
		if last_bounds.cursor_line != last_bounds.line:
			reset_selected_words()
			return

		editor.cursor_set_line(last_bounds.line)
		editor.cursor_set_column(last_bounds.cursor_column)

		var selected_text = _select_last_word(editor, last_bounds)

		var count_updated = {last_bounds.line: 0}
		var chars_diff: int = update_last_selected_word_length(editor, 1
		)
		var len_before_edit = len(editor.text)
		for i in range(selected_words.size()):
			var word = selected_words[i]
			var word_col = word[TextEdit.SEARCH_RESULT_COLUMN]
			var word_line = word[TextEdit.SEARCH_RESULT_LINE]

			if not count_updated.has(word_line):
				count_updated[word_line] = 0

			var count_chars: int = count_updated[word_line]
			selected_words[i][TextEdit.SEARCH_RESULT_COLUMN] -= count_chars

			editor.select(
				word_line, word_col - count_chars,
				word_line, word_col + len(last_selected_word) - count_chars
			)

			editor.cursor_set_line(word_line)
			if len(last_selected_word) == 0:
				editor.cursor_set_column(word_col - count_chars)
			else:
				editor.cursor_set_column(word_col)

			editor.insert_text_at_cursor(selected_text)

			# update column
			if selected_text:
				count_updated[word_line] += chars_diff
			else:
				count_updated[word_line] += len(last_selected_word)

		editor.cursor_set_line(last_bounds.line)
		editor.cursor_set_column(
			last_bounds.cursor_column - count_updated[last_bounds.line]
		)

		# restore last word
		selected_words.append(
			[
				last_bounds.column - count_updated[last_bounds.line],
				last_bounds.line
			]
		)

		last_selected_word = selected_text
		text_length = len(editor.text)
		editor.deselect()

		edit_num += 1
