class_name TutorialTopics
extends RefCounted

# Conteúdo do tutorial ensinado pelo Baldo (ver baldo.gd/tutorial_screen.gd).
# Cada entrada é um par (título, corpo) — o corpo é texto puro (sem BBCode),
# exibido num Label com autowrap dentro de um ScrollContainer (ver
# tutorial_topic_screen.gd), por isso quebras de parágrafo usam linha em
# branco em vez de qualquer marcação especial.
#
# Isso é, ao mesmo tempo, um tutorial de verdade pro jogador E um "resumo do
# que o sistema entende sobre o próprio jogo até agora" (pedido do usuário) —
# então cada texto aqui tenta bater exatamente com os números/regras
# implementados em código (battle.gd/unit.gd/game_state.gd/type_chart.gd),
# não uma versão simplificada ou aproximada. Se algum número aqui um dia
# destoar do código de verdade, o código é que está certo — isso aqui precisa
# ser atualizado, não o contrário.
#
# static (não @export/Resource) porque isso é só uma lista de dados fixos,
# sem motivo nenhum pra existir como Resource editável no Inspector.
static func get_topics() -> Array[Dictionary]:
	return [
		{
			"title": "Movimento e Bicicleta",
			"body": "Você anda pelo mundo em um grid: cada passo move o personagem exatamente 1 tile, sempre em uma das 4 direções (cima, baixo, esquerda, direita) — sem movimento livre em diagonal no mapa aberto.\n\nSegurar o botão de Correr deixa os passos mais rápidos (0.11s por tile, contra 0.22s andando normalmente), só isso — não troca o tipo de movimento, só a velocidade.\n\nA Bicicleta é diferente: não é uma tecla segurada, é um item Tool que você LIGA e DESLIGA usando ele na Bag — uma vez ligada, continua ligada até você usar de novo, mesmo trocando de mapa. De bicicleta, cada passo leva metade do tempo de Correr, a velocidade mais rápida do jogo.\n\nVocê pode registrar até 4 Tools em atalhos rápidos (teclas 1 a 4) pra não precisar abrir a Bag toda vez — é assim, por exemplo, que dá pra ligar/desligar a Bicicleta com um toque só."
		},
		{
			"title": "Grama Alta e Encontros Selvagens",
			"body": "Tiles de grama alta escondem Pokémon selvagens. Cada vez que você entra num tile desses, um contador regressivo (sorteado entre 5 e 15 passos) desce 1; quando ele chega a 0, a batalha começa e o contador é sorteado de novo pro próximo encontro.\n\nCada área do mapa tem sua própria tabela de encontros — uma lista de espécies possíveis, cada uma com uma faixa de nível — configurada num recurso separado que o jogo lê ao sortear o inimigo daquela batalha. Áreas diferentes podem ter tabelas completamente diferentes."
		},
		{
			"title": "NPCs e Cura",
			"body": "Personagens fixos do mundo (NPCs) ficam parados numa célula do grid, olhando pra uma direção. Ficar bem de frente pra um e apertar Confirmar (X) inicia a interação — o NPC vira automaticamente pra te encarar antes de qualquer coisa acontecer.\n\nA Enfermeira foi o primeiro NPC do jogo: falar com ela pergunta se você quer curar seu time (Sim/Não) e, se aceitar, restaura o HP e cura Status Conditions de toda a equipe ativa na hora — o mesmo efeito de um Centro Pokémon clássico."
		},
		{
			"title": "Deploy: Preparando a Batalha",
			"body": "Toda batalha começa numa fase de Deploy: o mapa (20x14 tiles) reserva uma faixa de 1/4 da largura como Zona de Deploy — só dentro dela você pode posicionar suas unidades antes do combate começar de verdade. O time adversário tem a zona espelhada do outro lado.\n\nParedes e fluidos do terreno (água, lava, e futuramente buracos) respeitam dois limites pensados pra nunca travar o deploy nem a movimentação de ninguém: juntos, eles nunca ocupam mais de 1/4 do mapa inteiro, e nunca mais da metade de uma zona de deploy."
		},
		{
			"title": "Ordem de Turno",
			"body": "Turnos não são 'seu time inteiro, depois o time inteiro do inimigo' — cada UNIDADE joga seu próprio turno, e a ordem entre todas (aliadas e inimigas misturadas) é definida pela Speed de cada uma: quem tem mais Speed joga primeiro.\n\nSe a Speed de alguém mudar NO MEIO da rodada (por um efeito que altere o estágio de Speed), a fila se reordena na hora — mas só entre quem ainda não jogou; ninguém que já agiu (ou está agindo agora) perde ou repete turno por causa disso."
		},
		{
			"title": "Movimento em Batalha e Terrenos",
			"body": "No seu turno, cada unidade tem um alcance de movimento igual a uma base de (5 - peso da unidade) tiles, mais 1 tile extra a cada 100 pontos de Speed efetiva. Unidades mais pesadas se movem menos; unidades mais rápidas ganham alcance extra.\n\nO caminho percorrido respeita obstáculos de verdade: paredes bloqueiam qualquer unidade, e tiles de fluido (água ou lava, dependendo do tileset sorteado pra aquela batalha) só deixam passar unidades do tipo certo (Water pra água, Fire pra lava) ou que não tocam o chão. Pisar num tile de lava sem ser do tipo certo aplica Burned na hora, automaticamente."
		},
		{
			"title": "Ações em Batalha",
			"body": "Cada unidade tem até 6 slots de ação equipados (o loadout) — cada slot pode ser um Ataque, uma Habilidade, ou um Item (incluindo TM e Ball). No seu turno você pode se mover E usar 1 Ataque; Habilidade e Item não gastam essa mesma trava (eles têm as próprias regras).\n\nAtaques com número limitado de usos descontam 1 uso do PRÓPRIO slot daquela unidade a cada vez que são usados — usar o mesmo ataque emprestado por um TM não gasta esse contador, gasta a pilha do item TM em vez disso."
		},
		{
			"title": "Fórmula de Dano e Tipos",
			"body": "O dano de um ataque segue a fórmula clássica: (((2*Nível/5 + 2) * Poder * Ataque/Defesa) / 50 + 2) * Modificadores, com truncamento (sem arredondar) em cada divisão.\n\nOs modificadores se multiplicam entre si: STAB (bônus de x1.5 se o tipo do ataque bate com o tipo da própria unidade), efetividade de tipo (a tabela clássica — dois tipos defensores multiplicam entre si, é assim que surgem os x4 e x0.25), Habilidades que reforçam um tipo específico em HP baixo, Sheer Force, e Acerto Crítico.\n\nEfetividade x0 (imunidade de tipo) sempre resulta em 0 de dano — não existe piso de 'mínimo 1' nesse caso; qualquer outro resultado é sempre pelo menos 1 de dano."
		},
		{
			"title": "Acertos Críticos",
			"body": "Todo ataque tem 6,25% de chance (1 em 16) de ser crítico, multiplicando o dano final por 1.5.\n\nUm crítico também ignora estágios de stat desfavoráveis: um Ataque/Sp.Atk REBAIXADO de quem ataca não conta contra o crítico (age como se estivesse em 0), e uma Defesa/Sp.Def AUMENTADA de quem defende também não protege — mas estágios FAVORÁVEIS (Ataque aumentado do atacante, Defesa rebaixada do defensor) continuam valendo normalmente, sem exceção."
		},
		{
			"title": "Status Conditions",
			"body": "Uma unidade só pode carregar UMA Status Condition por vez — tentar aplicar uma nova enquanto já tem outra simplesmente falha, mesmo que seja a mesma condição de novo. Cada tipo de imunidade abaixo vem do TIPO da própria unidade.\n\nPoisoned: perde 8% do HP máximo no fim de cada turno próprio; só sai por item/efeito de cura. Steel e Poison são imunes.\n\nBurned: reduz o dano de ataques FÍSICOS (não especiais) pela metade; só sai por item/efeito. Fire é imune.\n\nParalyzed: impede atacar. Electric é imune.\n\nFrozen: impede mover; descongela na hora ao tomar qualquer ataque tipo Fire. Ice é imune.\n\nAsleep: impede mover e atacar por até 3 turnos, ou até ser atingida por um ataque de verdade — o que vier primeiro.\n\nConfused e Blind: não bloqueiam ação, mas atrapalham (Blind reduz a chance de acerto pela metade).\n\nFlinched: trava mover e atacar, mas só nesse turno — é curada sozinha no começo do turno seguinte, diferente das outras condições com duração."
		},
		{
			"title": "Habilidades",
			"body": "Habilidades ocupam um slot de ação como qualquer Ataque/Item, mas não são 'usadas' no seu turno — ficam sempre ativas enquanto equipadas.\n\nExemplos: Habilidades como Blaze/Torrent aumentam o dano de ataques de um tipo específico quando o HP da unidade cai abaixo de 25%; Sheer Force aumenta o dano de ataques que teriam efeito secundário, mas cancela esse efeito por completo; e existem Habilidades de imunidade total a um tipo (o equivalente a Levitate contra Ground).\n\nUma unidade pode ter mais de uma Habilidade equipada ao mesmo tempo — os efeitos simplesmente se acumulam."
		},
		{
			"title": "Captura de Selvagens",
			"body": "Jogar uma Ball num inimigo selvagem rola a chance de captura pela fórmula clássica: quanto menor o HP restante do alvo, maior a chance, multiplicada pela taxa de captura própria da espécie e pelo bônus da Ball usada.\n\nStatus Conditions dão um bônus extra na chance: Asleep e Frozen valem o dobro do bônus normal; qualquer outra condição vale 1.5x. Uma Master Ball ignora a fórmula inteira e sempre captura.\n\nFalhar mostra a bola balançando de 0 a 2 vezes antes do Pokémon escapar; um sucesso sempre balança as 3 vezes antes de confirmar a captura."
		},
		{
			"title": "Experiência, Nível e Peso do Time",
			"body": "Vencer uma batalha distribui experiência pro seu time: quem deu o golpe final ganha 1.5x o valor calculado pela fórmula de EXP; os demais aliados que sobreviveram ganham 1x. Só unidades do jogador ganham XP de verdade — inimigos nunca sobem de nível no meio do próprio combate.\n\nSubir de nível recalcula todos os stats na hora, preservando o dano já sofrido: o HP atual sobe pela mesma quantidade que o HP máximo aumentou, em vez de curar tudo de graça.\n\nSeu time ativo tem um limite de peso combinado de 6 pontos, somando o peso (0 a 4) de cada unidade selecionada — a tela de armazenamento avisa e bloqueia se você tentar montar um time acima disso."
		},
		{
			"title": "Itens: Tools, TMs, Berries e Balls",
			"body": "A Bag organiza itens em categorias: Medicine (cura HP), Held Items, Berry, Tool, TM e Ball.\n\nBerry: qualquer Berry com efeito de cura se autoconsome sozinha assim que o HP da unidade cai abaixo de 50%, sem precisar de ordem sua — some do loadout como se tivesse sido usada de propósito.\n\nTool: efeito fora de batalha, sem gastar HP nem turno (ex: a Bicicleta) — até 4 podem ficar registrados em atalhos (teclas 1-4).\n\nTM: ensina/empresta um ataque específico pra quem carrega o item equipado — usar em batalha gasta uma carga da PILHA do próprio TM, não o contador de usos do ataque emprestado.\n\nBall: captura Pokémon selvagens em batalha (ver Captura de Selvagens)."
		},
	]
