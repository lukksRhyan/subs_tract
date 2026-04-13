import os
import json
from pathlib import Path

def carregar_gitignore(caminho_base):
    gitignore_path = Path(caminho_base) / ".gitignore"
    ignorar = set(('estrutura.json','gerar_json.py'))

    if gitignore_path.exists():
        with open(gitignore_path, "r", encoding="utf-8") as f:
            for linha in f:
                linha = linha.strip()
                if linha and not linha.startswith("#"):
                    ignorar.add(linha.rstrip("/"))
    return ignorar

def eh_ignorado(caminho_relativo, ignorar):
    partes = caminho_relativo.parts
    for ignorado in ignorar:
        if ignorado in partes or caminho_relativo.match(ignorado):
            return True
    return False

def ler_estrutura(caminho_base, ignorar):
    estrutura = {}

    for root, dirs, files in os.walk(caminho_base):
        caminho_relativo = Path(root).relative_to(caminho_base)
        if eh_ignorado(caminho_relativo, ignorar):
            dirs[:] = []  # Impede que subpastas sejam exploradas
            continue

        atual = estrutura
        for parte in caminho_relativo.parts:
            atual = atual.setdefault(parte, {})

        for nome_arquivo in files:
            print(f"Processando arquivo: {nome_arquivo}")
            caminho_arquivo = Path(root) / nome_arquivo
            rel_path = Path(root).relative_to(caminho_base) / nome_arquivo

            if eh_ignorado(rel_path, ignorar):
                continue

            try:
                with open(caminho_arquivo, "r", encoding="utf-8") as f:
                    conteudo = f.read()
                atual[nome_arquivo] = conteudo
            except Exception as e:
                atual[nome_arquivo] = f"<erro ao ler arquivo: {e}>"
    return estrutura

def salvar_yaml(estrutura, caminho_saida):
    with open(caminho_saida, "w", encoding="utf-8") as f:
        json.dump(estrutura, f, ensure_ascii=False, indent=4)

def main():
    caminho_base = Path(input("Insira o caminho do projeto: ")).resolve()
    ignorar = carregar_gitignore(caminho_base)
    estrutura = ler_estrutura(caminho_base, ignorar)
    salvar_yaml(estrutura, caminho_base / "estrutura.json")
    print("Arquivo estrutura.json gerado com sucesso.")

if __name__ == "__main__":
    main()
