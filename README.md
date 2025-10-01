# 🎬 Tradutor Automático de Legendas (Flutter Desktop)

Bem-vindo ao Tradutor Automático de Legendas! Este aplicativo de desktop, construído com Flutter, foi projetado para simplificar e agilizar o processo de tradução de legendas de vídeos. Com ele, você pode extrair legendas de arquivos de vídeo, prepará-las para tradução, e depois reinserir as legendas traduzidas de volta em um novo arquivo de vídeo, mantendo o estilo original.

## ✨ Funcionalidades

* Extração de Legendas: Extrai automaticamente a trilha de legenda em inglês de arquivos .mkv ou .mp4 para o formato .ass (Advanced SubStation Alpha).

* Preparação para Tradução: Gera um arquivo .json contendo apenas as falas do arquivo .ass extraído, pronto para ser enviado a um agente de IA ou serviço de tradução.

* Reintegração de Legendas: Permite selecionar o arquivo .json com as falas traduzidas.

* Recriação de Legenda Estilizada: Cria um novo arquivo .ass com as falas traduzidas, mantendo intactos os estilos originais (cores, tamanhos, posicionamentos).

* Inclusão no Vídeo Final: Gera um novo arquivo de vídeo (.mkv) com a legenda traduzida incorporada, substituindo a legenda original.

## 🚀 Como Usar

Siga estes passos simples para traduzir suas legendas:

1. Iniciar o Aplicativo: Abra o "Assistente de Tradução de Legendas".

2. 1. Selecionar Vídeo:

   * Clique no botão "1. Selecionar Vídeo".

   * Escolha o arquivo de vídeo (.mkv ou .mp4) que contém a legenda que você deseja traduzir.

   * O aplicativo irá automaticamente extrair a legenda, processá-la e gerar um arquivo .json com as falas.

   * O status na tela indicará a localização do arquivo .json gerado (ex: C:\Users\SeuUsuario\Documents\SeuVideo_legendas.json).

3. Traduzir o Arquivo JSON (Passo Manual):

   * Localize o arquivo .json que o aplicativo gerou no diretório indicado.

   * Envie este arquivo para seu agente de IA ou serviço de tradução preferido.

   * Certifique-se de que o arquivo traduzido mantenha a mesma estrutura JSON (uma lista de strings) e salve-o em um local de fácil acesso.

4. 2. Enviar JSON Traduzido:

   * Após obter o arquivo .json com as falas traduzidas, clique no botão "2. Enviar JSON Traduzido".

   * Selecione o arquivo .json que você traduziu.

   * O aplicativo irá agora recriar a legenda e incorporar no seu vídeo.

5. Vídeo Final:

   * Uma vez concluído o processo, o aplicativo informará a localização do novo arquivo de vídeo (.mkv) que contém as legendas traduzidas para português.

## 🛠️ Pré-requisitos (Para Desenvolvedores)

Se você é um desenvolvedor e deseja compilar ou modificar este projeto, você precisará:

* Flutter SDK: Versão estável com suporte a desktop habilitado.

  * Para habilitar o desktop, use: flutter config --enable-windows-desktop (ou macos-desktop, linux-desktop).

  * Verifique a instalação com: flutter doctor.

* FFmpeg: O ffmpeg é essencial para a manipulação de vídeo e áudio.

  * Instale o ffmpeg no seu sistema operacional.

  * Adicione o diretório do ffmpeg ao PATH do sistema. Para verificar, abra o terminal e digite ffmpeg -version.

* Dependências do Flutter: As dependências estão listadas no pubspec.yaml. Execute flutter pub get após clonar o projeto.

## ⚙️ Configuração do Ambiente (Para Desenvolvedores)

1. Clonar o repositório:

      git clone [URL_DO_SEU_REPOSITORIO]    cd [pasta_do_projeto]       

2. Obter dependências:

      flutter pub get       

3. Executar o aplicativo (em modo de desenvolvimento):

      flutter run -d windows # ou macos, ou linux       

4. Compilar para produção:

      flutter build windows # ou macos, ou linux       

## 💖 Contribuição

Contribuições são sempre bem-vindas! Sinta-se à vontade para abrir issues para bugs, sugerir novas funcionalidades ou enviar pull requests.

Desenvolvido com Flutter.
