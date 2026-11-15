class_name CareerProfilePage
extends CareerPage


func get_page_title() -> String:
	return "Player Profile"


func build_page() -> void:
	if add_no_career_notice():
		return
	var session := career()
	var me := session.human()
	if me == null:
		add_child(UIFactory.label("This career has no human professional.", &"WarningLabel"))
		return
	PlayerView.build(self, session.repo, me.id)
