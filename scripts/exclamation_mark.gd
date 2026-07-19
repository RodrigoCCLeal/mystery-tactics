extends AnimatedSprite2D

# Balão "!" que aparece acima da cabeça de um Trainer assim que ele avista o
# jogador (ver trainer.gd::_spot_player). Pedido do usuário: "The
# exclamation is an animation, use all sprites from the top row, left to
# right" (assets/sprites/effects/!.png tem vários ícones de balão
# diferentes espalhados pela folha — a fileira de CIMA, da esquerda pra
# direita, são os quadros desta animação em específico).
#
# sprite_frames (ver exclamation_mark.tscn) fica de propósito VAZIO neste
# script — é montado com a ferramenta visual do próprio Godot em vez de eu
# recortar coordenada de pixel no escuro (a mesma folha já causou um
# recorte errado uma vez, ver histórico do Region em Sprite2D):
#
#   1. Abra scenes/exclamation_mark.tscn, selecione o node ExclamationMark
#   2. Na aba inferior "Animation" (painel SpriteFrames), clique no ícone
#      de folha vazia -> "New SpriteFrames"
#   3. Clique no ícone de grade ("Add frames from Sprite Sheet"), escolha
#      assets/sprites/effects/!.png
#   4. Ajuste Horizontal/Vertical pra bater com o tamanho de cada quadro, e
#      clique nos quadros da FILEIRA DE CIMA, da esquerda pra direita, na
#      ordem certa (cada clique adiciona na ordem que você clicar)
#   5. Deixe o nome da animação como "default", desmarque "Loop", ajuste o
#      FPS a gosto (8~10 costuma ficar bom)
#
# play_and_wait() toca essa animação (uma vez só) e devolve pra quem chamou
# (await) somente depois dela terminar — é esse tempinho que dá "mais tempo
# entre avistar e a batalha começar" (outro pedido do usuário), antes da
# caixa de texto abrir em cima.

func _ready() -> void:
	# PROCESS_MODE_ALWAYS — precisa continuar animando mesmo com a árvore
	# pausada (trainer.gd pausa ANTES de instanciar isto, ver _spot_player).
	process_mode = Node.PROCESS_MODE_ALWAYS

# Nome próprio (não "play", que já é um método nativo de AnimatedSprite2D —
# sobrescrever ele em vez de só chamá-lo ia confundir mais do que ajudar)
# pra deixar claro, no lado de quem chama (trainer.gd), que isso ESPERA a
# animação terminar antes de continuar.
func play_and_wait() -> void:
	# Guard contra SpriteFrames ainda não configurado (ver instruções lá em
	# cima) — sem isso, "await animation_finished" travaria pra sempre (o
	# sinal nunca dispara sem animação nenhuma tocando), e trainer.gd
	# congelaria a sequência inteira de avistar+batalha sem erro nenhum
	# visível, só "nada acontece". Com o guard, pelo menos aparece um aviso
	# no Output apontando pra cá.
	if sprite_frames == null or not sprite_frames.has_animation("default"):
		push_warning("ExclamationMark sem SpriteFrames configurado ainda — ver instruções no topo de exclamation_mark.gd.")
		return
	play()
	# animation_finished só dispara quando uma animação SEM loop chega no
	# fim — com "Loop" ligado no SpriteFrames (é o caso aqui, ver
	# exclamation_mark.tscn), animation_finished NUNCA dispara, e esse
	# await ficava esperando pra sempre: era exatamente isso que fazia o
	# "!" tocar pra sempre e a caixa de texto nunca abrir. animation_looped
	# é o sinal certo pra animação COM loop — dispara toda vez que ela
	# termina uma volta e reinicia; esperamos só a primeira, e paramos ali
	# (pedido do usuário: "it was supposed to be a single cicle").
	if sprite_frames.get_animation_loop("default"):
		await animation_looped
	else:
		await animation_finished
	stop()
	# animation_looped dispara bem no instante em que o quadro volta pro 0
	# (o "wrap" da volta) — então, sem isso, stop() segurava a animação no
	# PRIMEIRO quadro, não no último (pedido do usuário: "the loop has to
	# end on the last frame, not the first"). Forçamos o quadro final aqui.
	frame = sprite_frames.get_frame_count("default") - 1
