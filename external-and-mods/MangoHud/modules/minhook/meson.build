minhook_src = [
	'src/buffer.c',
	'src/hook.c',
	'src/trampoline.c',
	'src/hde/hde32.c',
	'src/hde/hde64.c',
]

minhook = static_library('minhook',
    sources: minhook_src,
	include_directories: include_directories('src', 'include'),
)

minhook_dep = declare_dependency(
	include_directories: include_directories('src', 'include'),
	link_with: minhook
)