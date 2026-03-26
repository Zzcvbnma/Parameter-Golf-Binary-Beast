import torch
import torch.nn as nn
import torch.nn.functional as F

class BitLinear(nn.Linear):
    """
    Ranjit's 1-bit Custom Layer.
    Optimized for 16MB constraint and 8x H100 speed.
    """
    def forward(self, x):
        w = self.weight
        # Step 1: Weight Binarization (+1, -1)
        scale = w.abs().mean()
        w_bin = torch.sign(w) * scale
        
        # Step 2: Activation Normalization (RMSNorm style)
        x_norm = x - x.mean(dim=-1, keepdim=True)
        variance = x_norm.pow(2).mean(-1, keepdim=True)
        x_norm = x_norm * torch.rsqrt(variance + 1e-5)
        
        return F.linear(x_norm, w_bin, self.bias)

print("Binary Engine: 1-bit BitLinear logic successfully injected.")
