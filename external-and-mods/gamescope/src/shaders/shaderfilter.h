#ifndef SHADERFILTER_H
#define SHADERFILTER_H

const int shader_filter_max_bits = 4;

uint get_layer_shaderfilter(uint layerIdx) {
    return bitfieldExtract(u_shaderFilter, int(layerIdx) * shader_filter_max_bits, shader_filter_max_bits);
}

#endif